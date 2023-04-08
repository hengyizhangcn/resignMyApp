//
//  resignHelper.swift
//  resignTool
//
//  Created by zhanghengyi on 2019/3/6.
//  Copyright © 2019 zhy. All rights reserved.
//

import Foundation
import SwiftUI

/// 重签名帮助类
public class ResignHelper {
    
    /// 记录上次重签名对应的组名
    static var lastTeamName = ""
    /// 签名后IPA路径
    static var newIPAPath = ""
    
    /// execute the command and get the result
    ///
    /// - Parameters:
    ///   - launchPath: the full path of the command
    ///   - arguments: arguments
    /// - Returns: command execute result
    @discardableResult
    class func runCommand(launchPath: String, arguments: [String], printOut: Bool = false) -> Data {
        let pipe = Pipe()
        let file = pipe.fileHandleForReading
        
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments
        task.standardOutput = pipe
        task.launch()
        
        let data = file.readDataToEndOfFile()
        
        task.terminate()
        return data
    }
    
    /// remove middle files and directionary
    class func clearMiddleProducts() {
        
        runCommand(launchPath: "/bin/rm", arguments: ["-rf", "appEntitlements.plist"])
        runCommand(launchPath: "/bin/rm", arguments: ["-rf", "watchAppEntitlements.plist"])
        runCommand(launchPath: "/bin/rm", arguments: ["-rf", "watchAppAppexEntitlements.plist"])
        runCommand(launchPath: "/bin/rm", arguments: ["-rf", "mobileprovision.plist"])
        runCommand(launchPath: "/bin/rm", arguments: ["-rf", "Payload"])
        runCommand(launchPath: "/bin/rm", arguments: ["-rf", "AppThinning.plist"]) //for thin if exists
    }
    
    /// 移除暂存的new App文件夹
    class func clearNewAppDirectory() {
        runCommand(launchPath: "/bin/rm", arguments: ["-rf", "new App"])
    }
    
    /// abstract plist for app like framework, extension, appex, etc
    /// emphasis: if mobileprovisionPath is exist, abstract plist from the mobileprovisionPath, or from the appPath
    ///
    /// - Parameters:
    ///   - appPath: the appPath can be framework, extension, appex, etc
    ///   - mobileprovisionPath: the path of mobileprovision
    ///   - plistFilePath: target plist file
    class func abstractPlistFromMobileProvision(_ appPath: String, _ mobileprovisionPathTemp: String?, _ entitlementsFilePath: String) {
        
        if mobileprovisionPathTemp != nil && mobileprovisionPathTemp!.count > 0 {
            let mobileprovisionData = runCommand(launchPath: "/usr/bin/security", arguments: ["cms", "-D", "-i", mobileprovisionPathTemp!]);

            let fileUrl = URL.init(fileURLWithPath: "mobileprovision.plist")
            do {
                try mobileprovisionData.write(to: fileUrl)
            } catch {
                print(error)
            }
            

            let plistXML = FileManager.default.contents(atPath: fileUrl.path)!
            do {
                //read plist file to dictionary
                let plistDict = try PropertyListSerialization.propertyList(from: plistXML, options: .mutableContainersAndLeaves, format: nil) as! [String: Any]
                
                let EntitlementsDict = plistDict["Entitlements"]

                
                let plistFilePathUrl = URL.init(fileURLWithPath: entitlementsFilePath)
                
                if let plistOutputStream = OutputStream.init(toFileAtPath: plistFilePathUrl.path, append: false) {
                    
                    //should keep the outputstream open
                    plistOutputStream.schedule(in: RunLoop.current, forMode: .default)
                    plistOutputStream.open()
                    
                    //write the new plist content to file
                    PropertyListSerialization.writePropertyList(EntitlementsDict!, to: plistOutputStream, format: PropertyListSerialization.PropertyListFormat.xml, options: 0, error: nil)
                }
            } catch {
                print(error)
            }
            
        } else {

            runCommand(launchPath: "/usr/bin/codesign", arguments: ["-d", "--entitlements", entitlementsFilePath, appPath])
            do {
                let fileUrl = URL.init(fileURLWithPath: entitlementsFilePath)
                var entitleData = try Data.init(contentsOf: fileUrl)
                entitleData.removeSubrange(0..<8) //first eight characters are unknown, should be removed
                
                try entitleData.write(to: fileUrl)
            } catch {
                print(error)
            }
        }
        
    }
    
    /// config app bundld Id
    ///
    /// - Parameter appPath: the path of the app
    /// - Parameter bundleIdentifier: 主工程bundleId
    /// - Parameter WKCompanionAppBundleIdentifier: watchkit的宿主bundleId
    /// - Parameter WKAppBundleIdentifier: watchkit的bundleId
    class func configureInfoPlistContent(_ bundleIdentifier: String?, _ appPath: String, _ WKCompanionAppBundleIdentifier: String?, _ WKAppBundleIdentifier: String?) {
        
        let plistPath = appPath + "/Info.plist"
        let plistXML = FileManager.default.contents(atPath: plistPath)!
        do {
            //read plist file to dictionary
            var plistDict = try PropertyListSerialization.propertyList(from: plistXML, options: .mutableContainersAndLeaves, format: nil) as! [String: Any]
            
            
            if let shortVersion = plistDict["CFBundleShortVersionString"] {
                plistDict["CFBundleShortVersionString"] = "\(shortVersion)_Enterprise"
            }
            
            if let bundleIdentifier {
                plistDict["CFBundleIdentifier"] = bundleIdentifier
            }
            
            if let WKCompanionAppBundleIdentifier {
                plistDict["WKCompanionAppBundleIdentifier"] = WKCompanionAppBundleIdentifier
            }
            
            if let WKAppBundleIdentifier {
                var NSExtension = plistDict["NSExtension"] as? [String: Any]
                if let _ = NSExtension {
                    var NSExtensionAttributes = NSExtension?["NSExtensionAttributes"] as? [String: Any]
                    if let _ = NSExtensionAttributes {
                        NSExtensionAttributes?["WKAppBundleIdentifier"] = WKAppBundleIdentifier;
                    }
                    NSExtension?["NSExtensionAttributes"] = NSExtensionAttributes
                }
                plistDict["NSExtension"] = NSExtension
            }
            
            if let plistOutputStream = OutputStream.init(toFileAtPath: plistPath, append: false) {
                
                //should keep the outputstream open
                plistOutputStream.schedule(in: RunLoop.current, forMode: .default)
                plistOutputStream.open()
                
                //write the new plist content to file
                PropertyListSerialization.writePropertyList(plistDict, to: plistOutputStream, format: PropertyListSerialization.PropertyListFormat.xml, options: 0, error: nil)
            }
        } catch {
            print(error)
        }
    }
    
    /// replace provision and resign
    ///
    /// - Parameters:
    ///   - appPath: the appPath can be framework, extension, appex, etc
    ///   - provisionPath: mobileprovision
    ///   - plistFilePath: plist file
    class func replaceProvisionAndResign(_ appPath: String, _ provisionPath: String?, _ entitlementsFilePath: String) -> Bool {
        var TeamName: String?
        if provisionPath != nil && provisionPath!.count > 0 {
            let mobileprovisionData = runCommand(launchPath: "/usr/bin/security", arguments: ["cms", "-D", "-i", provisionPath!])
            
            do {
                let datasourceDictionary = try PropertyListSerialization.propertyList(from: mobileprovisionData, options: [], format: nil)
                
                if let dict = datasourceDictionary as? Dictionary<String, Any> {
                    TeamName = dict["TeamName"] as? String
                }
                
                //replace embedded.mobileprovision
                runCommand(launchPath: "/bin/cp", arguments: [provisionPath!, appPath + "/embedded.mobileprovision"])
            } catch {
                print(error)
            }
            
        } else {
            do {
                //if appPath + "/embedded.mobileprovision" does exist, read team name from the app
                let mobileprovisionData = runCommand(launchPath: "/usr/bin/security", arguments: ["cms", "-D", "-i", appPath + "/embedded.mobileprovision"])
                
                let datasourceDictionary = try PropertyListSerialization.propertyList(from: mobileprovisionData, options: [], format: nil)
                
                if let dict = datasourceDictionary as? Dictionary<String, Any> {
                    TeamName = dict["TeamName"] as? String
                }
            } catch {
                print(error)
            }
        }
        
        if lastTeamName == "" {
            lastTeamName = TeamName!
        } else if lastTeamName != TeamName! {
            showAlertWith(title: "多次签名需要的证书不是同一个", message: "请检查各描述文件的设置！", style: .critical)
            return false
        }
        
        //Remove old CodeSignature, can be ignored
        runCommand(launchPath: "/bin/rm", arguments: ["-rf", appPath + "_CodeSignature"])
        
        //resign extension/framework/app etc.
        let teamNameCombinedStr = "iPhone Distribution: " + TeamName!
        runCommand(launchPath: "/usr/bin/codesign", arguments: ["-fs", teamNameCombinedStr, "--entitlements", entitlementsFilePath, appPath])
        
        return true
    }
    
    /// 重签名framework文件夹下的文件
    /// - Parameters:
    ///   - componentFile: 待签名框架
    ///   - provisionPath: 签名文件
    ///   - plistFilePath: entitlements文件
    class func resignDylibs(_ componentFile: String?, _ provisionPath: String?, _ plistFilePath: String) {
        var TeamName: String?
        do {
            //if appPath + "/embedded.mobileprovision" doesnot exist, read team name from the app
            let mobileprovisionData = runCommand(launchPath: "/usr/bin/security", arguments: ["cms", "-D", "-i", provisionPath!])
            
            let datasourceDictionary = try PropertyListSerialization.propertyList(from: mobileprovisionData, options: [], format: nil)
            
            if let dict = datasourceDictionary as? Dictionary<String, Any> {
                TeamName = dict["TeamName"] as? String
            }
        } catch {
            print(error)
        }
        //resign extension/framework/app etc.
        let teamNameCombinedStr = "iPhone Distribution: " + TeamName!
        runCommand(launchPath: "/usr/bin/codesign", arguments: ["-fs", teamNameCombinedStr, "--entitlements", plistFilePath, componentFile!])
    }
    
    /// repack app
    ///
    /// - Parameter tempIpaPath: ipa path
    class func repackApp(_ tempIpaPath: String?) {
        
        let ipaName = URL.init(fileURLWithPath: tempIpaPath!).lastPathComponent
        
        let manager = FileManager.default
        
        let targetIPAPath = manager.currentDirectoryPath + "/new App/" + ipaName
        do {
            try manager.createDirectory(atPath: manager.currentDirectoryPath + "/new App/", withIntermediateDirectories: true, attributes: [:])
            runCommand(launchPath: "/usr/bin/zip", arguments: ["-r", targetIPAPath , "Payload/", "AppThinning.plist"])
        } catch {
            print(error)
        }
        self.newIPAPath = targetIPAPath
    }
    
    /// 找出frameworks下所有的文件
    /// - Parameter tempIpaPath: ipa文件路径
    class func findComponentsList(_ tempIpaPath: String) -> Array<String> {
        
        let manager = FileManager.default
        let path = tempIpaPath + "/Frameworks"
        
        do {
            let frameworks = try manager.contentsOfDirectory(atPath: path)
            return frameworks
        } catch {
            print(error)
        }
        return []
    }
    
    /// 提取bundle id， 及aps-environment
    /// - Parameter tempMobileprovisionPath:
    class func abstractBundleId(_ tempMobileprovisionPath: String) -> (String, String) {
        let mobileprovisionData = runCommand(launchPath: "/usr/bin/security", arguments: ["cms", "-D", "-i", tempMobileprovisionPath])
        
        do {
            let datasourceDictionary = try PropertyListSerialization.propertyList(from: mobileprovisionData, options: [], format: nil)
            
            if let dict = datasourceDictionary as? Dictionary<String, Any> {
                let Entitlements = dict["Entitlements"] as? Dictionary<String, Any>
                
                var appId = "", apsEnvironment = ""
                if let entitlementsDict = Entitlements {
                    let applicationIdentifier = entitlementsDict["application-identifier"] as? String
                    if let appIdStr = applicationIdentifier {
                        //去除teamId剩下的即为bundleId
                        var arr = appIdStr.split(separator: ".")
                        //去除第一个元素teamId
                        arr.removeFirst()
                        appId = arr.joined(separator: ".")
                    }
                    if let tempApsEnvironment = entitlementsDict["aps-environment"] as? String {
                        apsEnvironment = tempApsEnvironment
                    }
                    return (appId, apsEnvironment)
                }
            }
        } catch {
            print(error)
        }
        return ("", "")
    }
    
    
    // MARK: - Alert
    
    /// 显示警示框
    /// - Parameters:
    ///   - title: 标题
    ///   - message: 提示消息
    ///   - style: 类型
    class func showAlertWith(title: String?, message: String, style: NSAlert.Style) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title ?? "ResignTool"
            alert.informativeText = message
            alert.alertStyle = style
            alert.addButton(withTitle: "关闭")
            if let window = NSApp.keyWindow {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }
    
    /// 移动IPA 文件到目标路径
    /// - Parameter tpath: 目标路径
    class func moveIPAFile(tpath: String) {
        if newIPAPath.count > 0 {
            do{
                //如果已存在，先删除，否则拷贝不了
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: tpath){
                    try fileManager.removeItem(atPath: tpath)
                }
                try fileManager.moveItem(atPath: newIPAPath, toPath: tpath)
                clearNewAppDirectory()
            }catch{
                
            }
            
        }
    }
    
    class func analyseResignInfo(_ plistPath: String, resignTool: ResignTool) {
        
        let plistXML = FileManager.default.contents(atPath: plistPath)!
        do {
            //read plist file to dictionary
            let plistDict = try PropertyListSerialization.propertyList(from: plistXML, options: .mutableContainersAndLeaves, format: nil) as! [String: Any]
            
            if let mobileprovisionDict = plistDict["mobileprovision"] as? [String : String] {
                resignTool.appMobileprovisionPath = mobileprovisionDict["app"]
                resignTool.watchAppMobileprovisionPath = mobileprovisionDict["watchApp"]
                resignTool.watchAppAppexMobileprovisionPath = mobileprovisionDict["watchAppAppex"]
            }
            if let bundleIdDict = plistDict["bundleId"] as? [String : String] {
                resignTool.appBundleId = bundleIdDict["app"]
                resignTool.watchAppBundleId = bundleIdDict["watchApp"]
                resignTool.watchAppAppexBundleId = bundleIdDict["watchAppAppex"]
            }
        } catch {
            print(error)
        }
    }
}
