//
//  main.swift
//  resignMyApp
//
//  Created by hengyi.zhang on 2023/4/8.
//

import Foundation

//unzip .ipa file to the directory the same with ipaPath
// because xcrun cannot be used within an App Sandbox.
// close sandbox

let arguments = CommandLine.arguments

var ipaPath = ""
var resignInfoPath = ""

for argument in arguments {
    if argument.contains(".ipa") {
        ipaPath = argument
    } else if argument.contains(".plist") {
        resignInfoPath = argument
    }
}

if ipaPath == "" {
    print("the path of ipa is needed")
    exit(0)
} else if resignInfoPath == "" {
    print("the configuration plist is needed")
    exit(0)
}

//开始签名
let resignTool = ResignTool()
resignTool.ipaPath = ipaPath
ResignHelper.analyseResignInfo(resignInfoPath, resignTool: resignTool)


resignTool.resignAction({(step) in
    if step == 10 {
        print("Resign Done!")
    }
}, { (result) in
    if (!result) {
    }
})
