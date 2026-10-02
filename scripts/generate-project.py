#!/usr/bin/env python3
"""Generate the checked-in Xcode project deterministically. Python 3; no dependencies."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "HabitBuddy.xcodeproj"
objects = {}

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def add(key_name, isa, **fields):
    key = ident(key_name)
    objects[key] = {"isa": isa, **fields}
    return key

def serialize(value, depth=0):
    indent = "\t" * depth
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (depth + 1) + json.dumps(k) + " = " + serialize(v, depth + 1) + ";\n" for k, v in value.items()) + indent + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (depth + 1) + serialize(v, depth + 1) + ",\n" for v in value) + indent + ")"
    return json.dumps(str(value))

def file(path, file_type=None):
    types = {".swift": "sourcecode.swift", ".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements", ".xcconfig": "text.xcconfig", ".xcprivacy": "text.xml", ".md": "net.daringfireball.markdown"}
    return add("file:" + path, "PBXFileReference", lastKnownFileType=file_type or types.get(Path(path).suffix, "text"), path=path, sourceTree="SOURCE_ROOT")

def build_file(path, target, **extra):
    return add(f"build:{target}:{path}", "PBXBuildFile", fileRef=file(path), **extra)

shared = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Shared").rglob("*.swift"))
app_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "HabitBuddy").rglob("*.swift"))
widget_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Widgets").rglob("*.swift"))
app_product = add("product:app", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="HabitBuddy.app", sourceTree="BUILT_PRODUCTS_DIR")
widget_product = add("product:widget", "PBXFileReference", explicitFileType="wrapper.app-extension", includeInIndex=0, path="HabitBuddyWidgets.appex", sourceTree="BUILT_PRODUCTS_DIR")
products = add("products", "PBXGroup", children=[app_product, widget_product], name="Products", sourceTree="<group>")
config = file("Config/Signing.xcconfig")
groups = []
for name, paths in [("App", app_sources + ["HabitBuddy/Info.plist", "HabitBuddy/HabitBuddy.entitlements", "HabitBuddy/PrivacyInfo.xcprivacy"]), ("Shared", shared), ("Widgets", widget_sources + ["Widgets/Info.plist", "Widgets/Widgets.entitlements"]), ("Configuration", ["Config/Signing.xcconfig", "README.md", "Package.swift"] )]:
    groups.append(add("group:" + name, "PBXGroup", children=[file(p) for p in paths], name=name, sourceTree="<group>"))
assets = file("HabitBuddy/Assets.xcassets", "folder.assetcatalog")
objects[groups[0]]["children"].append(assets)
main_group = add("main-group", "PBXGroup", children=groups + [products], sourceTree="<group>")
common_settings = {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "27.0", "SWIFT_VERSION": "5.0", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "SWIFT_STRICT_CONCURRENCY": "targeted", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "TARGETED_DEVICE_FAMILY": "1", "MARKETING_VERSION": "1.0.0", "CURRENT_PROJECT_VERSION": "1", "CODE_SIGN_STYLE": "Automatic", "GENERATE_INFOPLIST_FILE": "NO"}

def configurations(label, settings):
    configs = []
    for mode in ["Debug", "Release"]:
        values = {**settings, "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym"}
        if mode == "Debug": values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        configs.append(add(f"config:{label}:{mode}", "XCBuildConfiguration", baseConfigurationReference=config, buildSettings=values, name=mode))
    return add("configs:" + label, "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

project_config = configurations("project", common_settings)
app_config = configurations("app", {"PRODUCT_NAME": "HabitBuddy", "PRODUCT_BUNDLE_IDENTIFIER": "$(BUDDY_BUNDLE_ID)", "INFOPLIST_FILE": "HabitBuddy/Info.plist", "CODE_SIGN_ENTITLEMENTS": "HabitBuddy/HabitBuddy.entitlements", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"], "SWIFT_EMIT_LOC_STRINGS": "YES"})
widget_config = configurations("widget", {"PRODUCT_NAME": "HabitBuddyWidgets", "PRODUCT_BUNDLE_IDENTIFIER": "$(BUDDY_BUNDLE_ID).widgets", "INFOPLIST_FILE": "Widgets/Info.plist", "CODE_SIGN_ENTITLEMENTS": "Widgets/Widgets.entitlements", "APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]})
app_phase = add("sources:app", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=[build_file(p, "app") for p in app_sources + shared], runOnlyForDeploymentPostprocessing=0)
widget_phase = add("sources:widget", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=[build_file(p, "widget") for p in widget_sources + shared], runOnlyForDeploymentPostprocessing=0)
app_resources = add("resources:app", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[add("build:assets", "PBXBuildFile", fileRef=assets), build_file("HabitBuddy/PrivacyInfo.xcprivacy", "app-resource")], runOnlyForDeploymentPostprocessing=0)
widget_resources = add("resources:widget", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[build_file("HabitBuddy/PrivacyInfo.xcprivacy", "widget-resource")], runOnlyForDeploymentPostprocessing=0)
app_frameworks = add("frameworks:app", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
widget_frameworks = add("frameworks:widget", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
proxy = add("widget-proxy", "PBXContainerItemProxy", containerPortal=ident("project"), proxyType=1, remoteGlobalIDString=ident("target:widget"), remoteInfo="HabitBuddyWidgets")
dependency = add("widget-dependency", "PBXTargetDependency", target=ident("target:widget"), targetProxy=proxy)
embed_file = add("embed-widget-file", "PBXBuildFile", fileRef=widget_product, settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
embed_phase = add("embed-widget", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13, files=[embed_file], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0)
app_target = add("target:app", "PBXNativeTarget", buildConfigurationList=app_config, buildPhases=[app_phase, app_frameworks, app_resources, embed_phase], buildRules=[], dependencies=[dependency], name="HabitBuddy", productName="HabitBuddy", productReference=app_product, productType="com.apple.product-type.application")
widget_target = add("target:widget", "PBXNativeTarget", buildConfigurationList=widget_config, buildPhases=[widget_phase, widget_frameworks, widget_resources], buildRules=[], dependencies=[], name="HabitBuddyWidgets", productName="HabitBuddyWidgets", productReference=widget_product, productType="com.apple.product-type.app-extension")
project = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2700", "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "27.0"}, widget_target: {"CreatedOnToolsVersion": "27.0"}}}, buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[app_target, widget_target])
PROJECT.mkdir(exist_ok=True)
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}) + "\n")
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="HabitBuddy.app" BlueprintName="HabitBuddy" ReferencedContainer="container:HabitBuddy.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="HabitBuddy.app" BlueprintName="HabitBuddy" ReferencedContainer="container:HabitBuddy.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="HabitBuddy.app" BlueprintName="HabitBuddy" ReferencedContainer="container:HabitBuddy.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_path = PROJECT / "xcshareddata/xcschemes/HabitBuddy.xcscheme"
scheme_path.parent.mkdir(parents=True, exist_ok=True); scheme_path.write_text(scheme)
print(f"Generated {len(objects)} project objects; {len(app_sources)} app files and {len(shared)} shared files.")
