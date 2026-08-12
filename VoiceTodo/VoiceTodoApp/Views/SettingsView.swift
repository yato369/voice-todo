import SwiftUI
import Speech
import AVFoundation

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("存储") {
                    LabeledContent("数据存储", value: "仅保存在本机")
                    LabeledContent("云同步", value: "未开启")
                }

                Section("权限") {
                    PermissionRow(
                        title: "麦克风",
                        granted: AVAudioSession.sharedInstance().recordPermission == .granted
                    )
                    PermissionRow(
                        title: "语音识别",
                        granted: SFSpeechRecognizer.authorizationStatus() == .authorized
                    )
                }
                Section("关于") {
                    LabeledContent("版本", value: "0.1.0")
                    Text("本地优先的语音待办。录音转文字，自动进入待办与日历，数据不出本机。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(granted ? "已授权" : "未授权")
                .foregroundStyle(granted ? Color.green : Color.red)
        }
    }
}
