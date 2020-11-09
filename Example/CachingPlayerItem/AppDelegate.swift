//
//  AppDelegate.swift
//  CachingPlayerItem
//
//  Created by sukov on 10/24/2020.
//  Copyright (c) 2020 sukov. All rights reserved.
//

import UIKit
import AVFoundation

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UINavigationController(rootViewController: ViewController())
        window?.makeKeyAndVisible()

        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.allowBluetoothA2DP])

        return true
    }
}
