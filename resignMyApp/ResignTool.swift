//
//  main.swift
//  resignTool
//
//  Created by zhy on 2018/11/6.
//  Copyright © 2018 zhy. All rights reserved.
//

import Foundation

/// 重签名工具
class ResignTool {
    let help =
        "  version: 1.2.0\n" +
            "  usage: resignTool [-h] [-i <path>] [-m <path>] [-v <version>] [-callKit <callkit>]\n" +
            "  -h   this help.\n" +
            "  -i   the path of .ipa file.\n" +
            "  -m   the path of .mobileprovision file.\n" +
            "  -v   the new version of the app.\n" +
            "  -b   the new bundle id of the app.\n" +
            "  -info   the basic info of this ipa(in the future).\n" +
            "       if the version is not set, and 1 will be automatically added to the last of version components which separated by charater '.'.\n" +
    "  Please contact if you have some special demmands."
    
    /// 主包路径
    var ipaPath: String?
    /// 主包签名文件路径
    var appMobileprovisionPath: String?
    /// watch签名文件路径
    var watchAppMobileprovisionPath: String?
    /// watch扩展签名文件路径
    var watchAppAppexMobileprovisionPath: String?
    var appBundleId: String?
    var watchAppBundleId: String?
    var watchAppAppexBundleId: String?
    
    /// 找到.app文件
    ///
    /// - Returns: .app文件
    @discardableResult
    func enumeratePayloadApp() -> String {
        let manager = FileManager.default
        do {
            let contents = try manager.contentsOfDirectory(atPath: "Payload")
            for fileName in contents {
                if fileName.contains(".app") {
                    return manager.currentDirectoryPath + "/Payload/" + fileName
                }
            }
            print("The .app file not exist!")
        } catch {
            return ""
        }
        return ""
    }
    
    /// 打印帮助
    func showHelp() {
        print(help)
        terminate()
    }
    
    /// terminate process
    func terminate() {
        exit(0)
    }
    
    /// 检查用户输入
    func checkUserInput() {
        let arguments = CommandLine.arguments
        
        //analysize user's input
        for i in 1..<arguments.count {
            
            let arg = arguments[i]
            
            switch (arg) {
            case "-m":
                if arguments.count > i {
                    appMobileprovisionPath = arguments[i + 1]
                }
                break
            case "-i":
                if arguments.count > i {
                    ipaPath = arguments[i + 1]
                }
                break
            case "-v":
                if arguments.count > i {
//                    newVersion = arguments[i + 1]
                }
                break
            case "-b":
                if arguments.count > i {
                    appBundleId = arguments[i + 1]
                }
                break
            case "-h":
                showHelp()
            case "-":
                print("bad option:"+arg)
                terminate()
            default:
                break;
            }
        }
        
        //check user's input
        if ipaPath == nil {
            print("The path of .ipa file doesnot exist, please point it out")
            terminate()
        }
    }
    
    /// 重签名流程
    /// - Parameters:
    ///   - actionProgress: 重签名进程回调
    ///   - resultBlock: 签名结果回调
    func resignAction(_ actionProgress: ((Double) -> ())?, _ resultBlock: ((Bool) -> ())?) {
        
        actionProgress?(0)
        
        // 重置初始值
        ResignHelper.lastTeamName = ""
        ResignHelper.newIPAPath = ""
        
        //remove middle files and directionary
        var appPath = enumeratePayloadApp()
        
        if appPath.count == 0 {
            ResignHelper.clearMiddleProducts()
            
            actionProgress?(1)
            
            //unzip .ipa file to the directory the same with ipaPath
            // because xcrun cannot be used within an App Sandbox.
            // close sandbox
            
            ResignHelper.runCommand(launchPath: "/usr/bin/unzip", arguments: [ipaPath!])
            
            actionProgress?(2)
            
            appPath = enumeratePayloadApp()
        }
        
        var watchAppPath = ""
        let manager = FileManager.default
        do {
            let watch = try manager.contentsOfDirectory(atPath: appPath + "/Watch/")
            for fileName in watch {
                if fileName.contains(".app") {
                    watchAppPath = appPath + "/Watch/" + fileName
                }
            }
        } catch {
            print("find watch error:", error)
        }
        
        var watchAppAppexPath = ""
        do {
            let plugIns = try manager.contentsOfDirectory(atPath: watchAppPath + "/PlugIns/")
            for fileName in plugIns {
                if fileName.contains(".appex") {
                    watchAppAppexPath = watchAppPath + "/PlugIns/" + fileName
                }
            }
        } catch {
            print("find watch appex error:", error)
        }
        
        let appEntitlementsFilePath = "app" + "Entitlements.plist"
        let watchAppEntitlementsFilePath = "watchApp" + "Entitlements.plist"
        let watchAppAppexEntitlementsFilePath = "watchAppAppex" + "Entitlements.plist"
        
        //abstract plist from mobileprovision
        // for app
        ResignHelper.abstractPlistFromMobileProvision(appPath, appMobileprovisionPath, appEntitlementsFilePath)
        // for watch
        ResignHelper.abstractPlistFromMobileProvision(watchAppPath, watchAppMobileprovisionPath, watchAppEntitlementsFilePath)
        // for appex
        ResignHelper.abstractPlistFromMobileProvision(watchAppAppexPath, watchAppAppexMobileprovisionPath, watchAppAppexEntitlementsFilePath);
        actionProgress?(3)
        
        // sign watch appex-----
        //update the bundle
        ResignHelper.configureInfoPlistContent(watchAppAppexBundleId, watchAppAppexPath, nil, watchAppBundleId)
        //resign appex
        var resignResult = ResignHelper.replaceProvisionAndResign(watchAppAppexPath, watchAppAppexMobileprovisionPath, watchAppAppexEntitlementsFilePath)
        if (!resignResult) {
            resultBlock?(false)
            return
        }
        actionProgress?(4)
        
        // sign watch app-----
        // update the bundle
        ResignHelper.configureInfoPlistContent(watchAppBundleId, watchAppPath, appBundleId, nil)
        //resign appex
        resignResult = ResignHelper.replaceProvisionAndResign(watchAppPath, watchAppMobileprovisionPath, watchAppEntitlementsFilePath)
        if (!resignResult) {
            resultBlock?(false)
            return
        }
        actionProgress?(5)
        
        
        ///sign dynamic framework
        let componentsList = ResignHelper.findComponentsList(appPath)
        for path in componentsList {
            
            let filePath = appPath + "/Frameworks/" + path
            
            ResignHelper.resignDylibs(filePath, appMobileprovisionPath, appEntitlementsFilePath)
        }
        actionProgress?(5.5)
        
        //update the app bundle
        ResignHelper.configureInfoPlistContent(appBundleId, appPath, nil, nil)
        actionProgress?(6)
        
        //resign app
        let resignAppResult = ResignHelper.replaceProvisionAndResign(appPath, appMobileprovisionPath, appEntitlementsFilePath)
        if (!resignAppResult) {
            resultBlock?(false)
            return
        }
        
        actionProgress?(7)
        
        //codesign -vv -d xxxx.app
        ResignHelper.runCommand(launchPath: "/usr/bin/codesign", arguments: ["-vv", "-d", appPath])
        
        
        actionProgress?(8)
        
        //repacked app
        //zip -r xxxx.ipa Payload/
        ResignHelper.repackApp(ipaPath)
        
        
        actionProgress?(9)
        
        //remove middle files and directionary
        ResignHelper.clearMiddleProducts()
        
        
        actionProgress?(10)
    }
}

