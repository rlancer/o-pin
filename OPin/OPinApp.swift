import Foundation
import SwiftData
import SwiftUI


@Model
class BrowserProfileModel {
  @Attribute(.unique) var email: String
  var path: String

  init(email: String, path: String) {
    self.email = email
    self.path = path
  }
}

@main
struct OPinApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    MenuBarExtra("Utility App", systemImage: "pin.fill") {
      ContentView3().modelContainer(for: BrowserProfileModel.self).environmentObject(appDelegate)
    }
  }
}

func requestChromeSupportDirectoryAccess() -> URL? {
  let openPanel = NSOpenPanel()
  openPanel.title = "Select Chrome Support Directory"
  openPanel.message = "Please select the Chrome support directory."
  openPanel.canChooseDirectories = true
  openPanel.canChooseFiles = false
  openPanel.allowsMultipleSelection = false
  openPanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library")
    .appendingPathComponent("Application Support")
    .appendingPathComponent("Google")
    .appendingPathComponent("Chrome")

  if openPanel.runModal() == .OK {
    if let url = openPanel.url {
      do {
        let bookmarkData = try url.bookmarkData(
          options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmarkData, forKey: "ChromeSupportDirectoryBookmark")
        return url
      } catch {
        print("Failed to create bookmark: \(error)")
        return nil
      }
    }
  }
  return nil
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  @Published var selectedProfile = "---"

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      print("Received URL: \(url)")
      openURLInChrome(url)
    }
  }

  func openURLInChrome(_ url: URL) {
      let task = Process()
      task.launchPath = "/bin/sh"

      let argss = ["-c", "open -na \"Google Chrome\" --args --profile-directory=\"\(selectedProfile)\" \(url)"]
      print(argss)
      task.arguments = argss

      try?   task.run()
     task.waitUntilExit()
  }
}

struct ContentView3: View {

  @EnvironmentObject var appDelegate: AppDelegate
  @State var selectedProfile = "---"
  @Environment(\.modelContext) var modelContext
  @Query private var profiles: [BrowserProfileModel]

  var body: some View {

    let selectedProfileBinding = Binding<String>(
      get: {
        return appDelegate.selectedProfile
      },
      set: {
        appDelegate.selectedProfile = $0
      })

    Button(
      action: {
        Task { @MainActor in
          await setDefaultApp()
        }
      },
      label: {
        Text("Set as Default Browser")
      }
    )

    Divider()

    Picker(
      "Route to Chrome Profile \(appDelegate.selectedProfile)", selection: selectedProfileBinding
    ) {
      Text("Don't route").tag("---")
      ForEach(Array(profiles.enumerated()), id: \.element) { index, profile in
          Text(profile.email).tag(profile.path)
      }
    }
    .pickerStyle(.inline)

    Divider()

    Button(
      action: {
        loadChromeProfiles()
      },

      label: {
        Text("Sync Chrome Profiles")
      })
      
      
      Button(
        action: {
            NSApplication.shared.terminate(nil)
        },

        label: {
          Text("Quit")
        })
  }

  func setDefaultApp() async {
    do {
      try await NSWorkspace.shared.setDefaultApplication(
        at: Bundle.main.bundleURL,
        toOpenURLsWithScheme: "http"
      )
    } catch {
      print("Failed to set default application: \(error)")
    }
  }

  func loadChromeProfiles() {
    do {
      profiles.forEach { profile in
        modelContext.delete(profile)
      }
        
      print("Load chrome profiles")
      let fileManager = FileManager.default

      if let accessDirectoryURL = requestChromeSupportDirectoryAccess() {
        print("GOTaaaa \(accessDirectoryURL)")

        let contents = try fileManager.contentsOfDirectory(
          at: accessDirectoryURL, includingPropertiesForKeys: nil, options: [])
        for content in contents {

          if content.lastPathComponent.starts(with: /Profile/) {

            let preferencesPath = content.appendingPathComponent("Preferences")

            let data = try Data(contentsOf: preferencesPath)

            if let json = try JSONSerialization.jsonObject(with: data, options: [])
              as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let name = profile["name"] as? String,
              let accountInfo = json["account_info"] as? [[String: Any]]
            {
              var email: String = ""

              if !accountInfo.isEmpty {

                if let firstAccount = accountInfo.first {
                  // Access the email field
                  if let emailM = firstAccount["email"] as? String {
                    print("Email: \(emailM)")
                    email = emailM
                  } else {
                    print("Email key not found or not a string.")
                  }
                } else {
                  print("Failed to access the first account.")
                }
              }
                
                if (email.isEmpty){
                    continue
                }

                print("PATH: \(content.lastPathComponent)")
              modelContext.insert(BrowserProfileModel(email: email, path: content.lastPathComponent))
              print("namez \(name) email \(email)")
            } else {
              print("Could not parse JSON or find profile name.")
            }
          }
        }
      }
    } catch {
      print(error)
    }
  }
}
