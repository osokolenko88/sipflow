cask "sipflow" do
  version "1.0"
  sha256 "95a841c00337c7224d9ad531496d4599ed0dc6f79e25c4fee784b1eb13dbf4cc"

  url "https://github.com/OWNER/sipflow/releases/download/v#{version}/SIPflow-#{version}.zip"
  name "SIPflow"
  desc "SIP softphone for macOS"
  homepage "https://github.com/OWNER/sipflow"

  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "SIPflow.app"

  zap trash: [
    "~/Library/Application Support/SIPflow",
    "~/Library/Preferences/com.sipflow.app.plist",
    "~/Library/Saved Application State/com.sipflow.app.savedState",
  ]

  caveats <<~EOS
    SIPflow is signed with a self-signed certificate and is not notarized,
    so macOS quarantines it and Gatekeeper refuses the first launch.

    Clear the quarantine flag once after installing:
      xattr -dr com.apple.quarantine /Applications/SIPflow.app

    Alternatively build from source — a locally built app is never
    quarantined and needs no extra step.
  EOS
end
