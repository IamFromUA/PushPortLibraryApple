#!/usr/bin/env python3
"""Generate an independent iOS app + extension consuming the public Git package.

The fixture never initializes PushPort or requests permissions/network access.
Use --revision before release; use --version to verify an immutable release tag.
"""
import argparse
import pathlib
import re

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
ref = parser.add_mutually_exclusive_group(required=True)
ref.add_argument('--revision')
ref.add_argument('--version')
args = parser.parse_args()
if args.revision and not re.fullmatch(r'[0-9a-f]{40}', args.revision):
    parser.error('Expected a full Git revision')
if args.version and not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
    parser.error('Expected a release version')
root = pathlib.Path(args.output).resolve()
root.mkdir(parents=True, exist_ok=True)
project = root / 'Consumer.xcodeproj'
project.mkdir(exist_ok=True)
requirement = ('kind = revision; revision = "' + args.revision + '";') if args.revision else ('kind = exactVersion; version = "' + args.version + '";')

# Stable IDs keep this generated project reviewable without an Xcode project-generator dependency.
objects = {}
def ident(n):
    return f'{n:024X}'
def obj(n, kind, fields):
    objects[n] = f'isa = {kind}; {fields}'
def ids(*values):
    return '(' + ', '.join(ident(v) for v in values) + ',)'

obj(1, 'PBXProject', f'buildConfigurationList = {ident(40)}; compatibilityVersion = "Xcode 14.0"; mainGroup = {ident(2)}; productRefGroup = {ident(3)}; projectDirPath = ""; projectRoot = ""; targets = {ids(10, 11)}; packageReferences = {ids(50)}; attributes = {{LastUpgradeCheck = 1600;}};')
obj(2, 'PBXGroup', f'children = {ids(20, 21, 3)}; sourceTree = "<group>";')
obj(3, 'PBXGroup', f'name = Products; children = {ids(22, 23)}; sourceTree = "<group>";')
obj(20, 'PBXFileReference', 'lastKnownFileType = sourcecode.swift; path = ConsumerApp.swift; sourceTree = "<group>";')
obj(21, 'PBXFileReference', 'lastKnownFileType = sourcecode.swift; path = NotificationService.swift; sourceTree = "<group>";')
obj(22, 'PBXFileReference', 'explicitFileType = wrapper.application; path = Consumer.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj(23, 'PBXFileReference', 'explicitFileType = "wrapper.app-extension"; path = NotificationService.appex; sourceTree = BUILT_PRODUCTS_DIR;')
obj(24, 'PBXBuildFile', f'fileRef = {ident(20)};')
obj(25, 'PBXBuildFile', f'fileRef = {ident(21)};')
obj(26, 'PBXBuildFile', f'productRef = {ident(51)};')
obj(27, 'PBXBuildFile', f'productRef = {ident(52)};')
obj(28, 'PBXBuildFile', f'fileRef = {ident(23)}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy,);}};')
obj(30, 'PBXSourcesBuildPhase', f'buildActionMask = 2147483647; files = {ids(24)}; runOnlyForDeploymentPostprocessing = 0;')
obj(31, 'PBXSourcesBuildPhase', f'buildActionMask = 2147483647; files = {ids(25)}; runOnlyForDeploymentPostprocessing = 0;')
obj(32, 'PBXFrameworksBuildPhase', f'buildActionMask = 2147483647; files = {ids(26)}; runOnlyForDeploymentPostprocessing = 0;')
obj(33, 'PBXFrameworksBuildPhase', f'buildActionMask = 2147483647; files = {ids(27)}; runOnlyForDeploymentPostprocessing = 0;')
obj(34, 'PBXCopyFilesBuildPhase', f'buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = {ids(28)}; name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
obj(35, 'PBXContainerItemProxy', f'containerPortal = {ident(1)}; proxyType = 1; remoteGlobalIDString = {ident(11)}; remoteInfo = NotificationService;')
obj(36, 'PBXTargetDependency', f'target = {ident(11)}; targetProxy = {ident(35)};')
obj(10, 'PBXNativeTarget', f'name = Consumer; productName = Consumer; productType = "com.apple.product-type.application"; productReference = {ident(22)}; buildConfigurationList = {ident(41)}; buildPhases = {ids(30,32,34)}; buildRules = (); dependencies = {ids(36)}; packageProductDependencies = {ids(51)};')
obj(11, 'PBXNativeTarget', f'name = NotificationService; productName = NotificationService; productType = "com.apple.product-type.app-extension"; productReference = {ident(23)}; buildConfigurationList = {ident(42)}; buildPhases = {ids(31,33)}; buildRules = (); dependencies = (); packageProductDependencies = {ids(52)};')
common = 'IPHONEOS_DEPLOYMENT_TARGET = 15.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; CODE_SIGNING_ALLOWED = NO; TARGETED_DEVICE_FAMILY = "1,2";'
app = 'PRODUCT_BUNDLE_IDENTIFIER = dev.pushport.publication.consumer; PRODUCT_NAME = "$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0;'
extension = 'PRODUCT_BUNDLE_IDENTIFIER = dev.pushport.publication.consumer.notification; PRODUCT_NAME = "$(TARGET_NAME)"; INFOPLIST_FILE = Extension-Info.plist; GENERATE_INFOPLIST_FILE = NO; APPLICATION_EXTENSION_API_ONLY = YES; SKIP_INSTALL = YES; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0;'
for config_id, values in [(43,common),(44,app),(45,extension)]:
    obj(config_id, 'XCBuildConfiguration', f'name = Debug; buildSettings = {{{values}}};')
for config_id, value in [(40,43),(41,44),(42,45)]:
    obj(config_id, 'XCConfigurationList', f'buildConfigurations = {ids(value)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
obj(50, 'XCRemoteSwiftPackageReference', f'repositoryURL = "https://github.com/IamFromUA/PushPortLibraryApple.git"; requirement = {{{requirement}}};')
obj(51, 'XCSwiftPackageProductDependency', f'package = {ident(50)}; productName = PushPort;')
obj(52, 'XCSwiftPackageProductDependency', f'package = {ident(50)}; productName = PushPortNotificationService;')
text = '// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
text += '\n'.join(f'{ident(n)} = {{{value}}};' for n, value in objects.items())
text += f'\n}}; rootObject = {ident(1)};}}\n'
(project / 'project.pbxproj').write_text(text, encoding='utf-8')
(root / 'ConsumerApp.swift').write_text('''import SwiftUI
import PushPort

@main
struct ConsumerApp: App {
    // Retaining the public Objective-C bridge exercises linking of the KMP-facing API.
    private let bridge = PushPortKMPBridge()
    var body: some Scene {
        WindowGroup { Text("PushPort " + PushPort.version).accessibilityIdentifier("sdk-version") }
    }
}
''', encoding='utf-8')
(root / 'NotificationService.swift').write_text('''import PushPortNotificationService

final class NotificationService: PushPortNotificationService {}
''', encoding='utf-8')
(root / 'Extension-Info.plist').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
<key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
<key>CFBundleName</key><string>$(PRODUCT_NAME)</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSExtension</key><dict>
<key>NSExtensionPointIdentifier</key><string>com.apple.usernotifications.service</string>
<key>NSExtensionPrincipalClass</key><string>$(PRODUCT_MODULE_NAME).NotificationService</string>
</dict></dict></plist>
''', encoding='utf-8')
print(project)
