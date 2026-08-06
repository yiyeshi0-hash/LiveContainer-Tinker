//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

struct LCTabView: View {
    @State var errorShow = false
    @State var crashReportShow = false
    @State var errorInfo = ""
    
    @State var previousSelectedTab : LCTabIdentifier = .apps
    
    @EnvironmentObject var sharedModel : SharedModel
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @State var shouldToggleMainWindowOpen = false
    @Environment(\.scenePhase) var scenePhase
    @StateObject var downloadHelper = DownloadHelper()
    
    @StateObject var searchContextAppList = SearchContext()
    @StateObject var searchContextSource = SearchContext()
    
    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)
    
    private var appListView: LCAppListView {
        LCAppListView(searchContext: searchContextAppList)
    }
    
    private var sourcesView: LCSourcesView {
        LCSourcesView(searchContext: searchContextSource)
    }

    
    var body: some View {
        Group {
            if #available(iOS 19.0, *), SharedModel.isLiquidGlassSearchEnabled {
                TabView(selection: $sharedModel.selectedTab) {
                    if DataManager.shared.model.multiLCStatus != 2 {
                        Tab("lc.tabView.sources".loc, systemImage: "books.vertical", value: LCTabIdentifier.sources) {
                            sourcesView
                        }
                    }
                    Tab("lc.tabView.apps".loc, systemImage: "square.stack.3d.up.fill", value: LCTabIdentifier.apps) {
                        appListView
                    }
                    if DataManager.shared.model.multiLCStatus != 2 {
                        Tab("lc.tabView.tweaks".loc, systemImage: "wrench.and.screwdriver", value: LCTabIdentifier.tweaks) {
                            LCTweaksView()
                        }
                    }
                    Tab("折腾中心", systemImage: "hammer", value: LCTabIdentifier.tinker) {
                        TinkerCenterView()
                    }
                    Tab("lc.tabView.settings".loc, systemImage: "gearshape.fill", value: LCTabIdentifier.settings) {
                        LCSettingsView()
                    }
                }
            } else {
                TabView(selection: $sharedModel.selectedTab) {
                    if DataManager.shared.model.multiLCStatus != 2 {
                        sourcesView
                            .tabItem {
                                Label("lc.tabView.sources".loc, systemImage: "books.vertical")
                            }
                            .tag(LCTabIdentifier.sources)
                    }
                    appListView
                        .tabItem {
                            Label("lc.tabView.apps".loc, systemImage: "square.stack.3d.up.fill")
                        }
                        .tag(LCTabIdentifier.apps)
                    if DataManager.shared.model.multiLCStatus != 2 {
                        LCTweaksView()
                            .tabItem{
                                Label("lc.tabView.tweaks".loc, systemImage: "wrench.and.screwdriver")
                            }
                            .tag(LCTabIdentifier.tweaks)
                    }

                    TinkerCenterView()
                        .tabItem {
                            Label("折腾", systemImage: "hammer")
                        }
                        .tag(LCTabIdentifier.tinker)
                    
                    LCSettingsView()
                        .tabItem {
                            Label("lc.tabView.settings".loc, systemImage: "gearshape.fill")
                        }
                        .tag(LCTabIdentifier.settings)
                }
            }
        }
        .downloadAlert(helper: downloadHelper)
        .environmentObject(downloadHelper)
        .alert("lc.common.error".loc, isPresented: $errorShow){
            Button("lc.common.ok".loc, action: {
            })
            Button("lc.common.copy".loc, action: {
                copyError()
            })
        } message: {
            Text(errorInfo)
        }
        .sheet(isPresented: $crashReportShow) {
            NavigationView {
                ScrollView {
                    Text(errorInfo)
                        .font(.system(size: 12).monospaced())
                        .fixedSize(horizontal: false, vertical: false)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("lc.common.copy".loc, action: {
                            copyError()
                        })
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("lc.common.ok".loc, action: {
                            crashReportShow = false
                        })
                    }
                }
                .navigationTitle("lc.common.error".loc)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            closeDuplicatedWindow()
            checkLastLaunchError()
            checkTeamId()
            checkAndSaveBundleId()
            checkGetTaskAllow()
            checkPrivateContainerBookmark()
        }
        .onReceive(pub) { out in
            if let scene1 = sceneDelegate.window?.windowScene, let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
                if shouldToggleMainWindowOpen {
                    DataManager.shared.model.mainWindowOpened = false
                }
            }
        }
        .onChange(of: sharedModel.selectedTab) { newValue in
            if newValue != LCTabIdentifier.search {
                previousSelectedTab = newValue
            }
        }
        .onOpenURL { url in
            dispatchURL(url: url)
        }
    }
    
    func dispatchURL(url: URL) {
        repeat {
            if url.isFileURL {
                sharedModel.selectedTab = .apps
                break
            }
            if url.scheme?.lowercased() == "sidestore" {
                sharedModel.selectedTab = .apps
                break
            }
            
            guard let host = url.host?.lowercased() else {
                return
            }
            
            switch host {
            case "livecontainer-launch", "install", "open-web-page", "open-url":
                sharedModel.selectedTab = .apps
            case "certificate":
                sharedModel.selectedTab = .settings
            case "source":
                sharedModel.selectedTab = .sources
            case "tinker":
                sharedModel.selectedTab = .tinker
            default:
                return
            }
            
        } while(false)

        sharedModel.deepLink = url
    }
    
    func closeDuplicatedWindow() {
        if let session = sceneDelegate.window?.windowScene?.session, DataManager.shared.model.mainWindowOpened {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { e in
                print(e)
            }
        } else {
            shouldToggleMainWindowOpen = true
        }
        DataManager.shared.model.mainWindowOpened = true
    }
    
    func checkLastLaunchError() {
        var errorStr = UserDefaults.standard.string(forKey: "error")
        
        if errorStr == nil && UserDefaults.standard.bool(forKey: "SigningInProgress") {
            errorStr = "lc.signer.crashDuringSignErr".loc
            UserDefaults.standard.removeObject(forKey: "SigningInProgress")
        }
        
        guard let errorStr else {
            markAutoStatus(error: nil)
            return
        }
        UserDefaults.standard.removeObject(forKey: "error")
        errorInfo = errorStr
        crashReportShow = true
        markAutoStatus(error: errorStr)
    }

    func markAutoStatus(error: String?) {
        guard let candidatePath = UserDefaults.standard.string(forKey: "LCLaunchCandidateBundlePath") else {
            return
        }
        let allApps = DataManager.shared.model.apps + DataManager.shared.model.hiddenApps
        guard let app = allApps.first(where: {
            ($0.appInfo.relativeBundlePath as String?) == candidatePath
        }) else {
            return
        }

        let startDate = UserDefaults.standard.object(forKey: "LCLaunchCandidateDate") as? Date ?? Date()
        let crashDate = crashMarkerDate() ?? (UserDefaults.standard.object(forKey: "LCLaunchCrashDate") as? Date)
        let elapsed = crashDate.map { $0.timeIntervalSince(startDate) } ?? 0
        let status: String
        if let crashDate {
            status = elapsed > 15 ? "Partial" : "Broken"
            _ = crashDate
        } else if error != nil {
            status = "Broken"
        } else {
            status = "Works"
        }
        app.appInfo.tinkerStatus = status
        if let error {
            let oldNotes = app.appInfo.tinkerNotes ?? ""
            let prefix = oldNotes.isEmpty ? "" : oldNotes + "\n"
            let trimmed = String(error.prefix(500))
            app.appInfo.tinkerNotes = prefix + "Auto: \(trimmed)"
        }
        app.objectWillChange.send()

        UserDefaults.standard.removeObject(forKey: "LCLaunchCandidateBundlePath")
        UserDefaults.standard.removeObject(forKey: "LCLaunchCandidateDate")
        UserDefaults.standard.removeObject(forKey: "LCLaunchCrashDate")
    }

    func crashMarkerDate() -> Date? {
        guard let home = ProcessInfo.processInfo.environment["LC_HOME_PATH"] else { return nil }
        let markerURL = URL(fileURLWithPath: home).appendingPathComponent("Documents/LCLaunchCrashMarker")
        guard let text = try? String(contentsOf: markerURL, encoding: .utf8),
              let timestamp = TimeInterval(text) else {
            return nil
        }
        try? FileManager.default.removeItem(at: markerURL)
        return Date(timeIntervalSince1970: timestamp)
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }
    
    func checkTeamId() {
        if let certificateTeamId = UserDefaults.standard.string(forKey: "LCCertificateTeamId") {
            if DataManager.shared.model.multiLCStatus != 2 {
                return
            }
            
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if certificateTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
            return
        }
        
        guard let currentTeamId = LCSharedUtils.teamIdentifier() else {
            print("Failed to determine team id.")
            return
        }
        
        if DataManager.shared.model.multiLCStatus == 2 {
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if currentTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
        }
        UserDefaults.standard.set(currentTeamId, forKey: "LCCertificateTeamId")
    }
    
    func checkAndSaveBundleId() {
        if DataManager.shared.model.multiLCStatus == 2 {
            let scheme = UserDefaults.lcAppUrlScheme() ?? ""
            LCUtils.appGroupUserDefault.set(Bundle.main.bundleIdentifier, forKey: "LCBundleID.\(scheme)")
        }
        
        if UserDefaults.standard.bool(forKey: "LCBundleIdChecked") {
            return
        }
        
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "application-identifier" as CFString, nil), let appIdentifier = value.takeRetainedValue() as? String else {
            errorInfo = "Unable to determine application-identifier"
            errorShow = true
            return
        }
        
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return
        }
        
        var correctBundleId = ""
        if appIdentifier.count > 11 {
            let startIndex = appIdentifier.index(appIdentifier.startIndex, offsetBy: 11)
            correctBundleId = String(appIdentifier[startIndex...])
        }
        
        if(bundleId != correctBundleId) {
            errorInfo = "lc.settings.bundleIdMismatch %@ %@".localizeWithFormat(bundleId, correctBundleId)
            errorShow = true
        }
        UserDefaults.standard.set(true, forKey: "LCBundleIdChecked")
    }
    
    func checkGetTaskAllow() {
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "get-task-allow" as CFString, nil), (value.takeRetainedValue() as? NSNumber)?.boolValue ?? false else {
            errorInfo = "lc.settings.notDevCert".loc
            errorShow = true
            return
        }
    }
    
    func checkPrivateContainerBookmark() {
        if sharedModel.multiLCStatus == 2 {
            return
        }
        if LCUtils.appGroupUserDefault.object(forKey: "LCLaunchExtensionPrivateDocBookmark") != nil {
            return
        }
        
        guard let bookmark = LCUtils.bookmark(for: LCPath.docPath) else {
            errorInfo = "Failed to create bookmark for Documents folder?"
            errorShow = true
            return
        }
        LCUtils.appGroupUserDefault.set(bookmark, forKey: "LCLaunchExtensionPrivateDocBookmark")
    }
}
