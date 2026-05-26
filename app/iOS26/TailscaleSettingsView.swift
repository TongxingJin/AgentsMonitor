import SwiftUI

struct TailscaleSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hosts: [String]
    @State private var newHost = ""
    let onSave: ([String]) -> Void

    init(initialHosts: [String], onSave: @escaping ([String]) -> Void) {
        _hosts = State(initialValue: initialHosts)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(hosts, id: \.self) { host in
                        Text(host)
                            .font(.system(.body, design: .monospaced))
                    }
                    .onDelete { indexSet in
                        hosts.remove(atOffsets: indexSet)
                    }

                    HStack {
                        TextField("100.x.x.x 或 hostname", text: $newHost)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button("添加") {
                            let h = newHost.trimmingCharacters(in: .whitespaces)
                            guard !h.isEmpty, !hosts.contains(h) else { return }
                            hosts.append(h)
                            newHost = ""
                        }
                        .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Tailscale 主机")
                } footer: {
                    Text("输入运行 beacon 的机器的 Tailscale IP 或 MagicDNS hostname，自动使用端口 8765。")
                }
            }
            .navigationTitle("Tailscale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSave(hosts)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
