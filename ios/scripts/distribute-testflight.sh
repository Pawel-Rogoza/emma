#!/usr/bin/env bash
# Uruchamiany wyłącznie na macOS runnerze GitHub Actions.
set -euo pipefail

required=(
  IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64
  IOS_DISTRIBUTION_CERTIFICATE_PASSWORD
  IOS_DISTRIBUTION_PROFILE_BASE64
  ASC_KEY_ID
  ASC_ISSUER_ID
  ASC_PRIVATE_KEY_P8
  GITHUB_RUN_ID
  RUNNER_TEMP
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Brakuje wartości: $name" >&2
    exit 1
  fi
done

bundle_id=pl.kancelaria.emma.staging
team_id=QZ25N94YZ8
if ! grep -Eq '^EMMA_VOICE_PROVIDER[[:space:]]*=[[:space:]]*gemini_live[[:space:]]*$' Config/Staging.xcconfig; then
  echo 'Build Staging nie wskazuje Gemini Live.' >&2
  exit 1
fi

work_dir="$(mktemp -d "${RUNNER_TEMP}/emma-testflight.XXXXXX")"
keychain_path="${work_dir}/signing.keychain-db"
profile_path=""
api_key_path="${HOME}/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
cleanup() {
  if [[ -n "$profile_path" ]]; then rm -f "$profile_path"; fi
  rm -f "$api_key_path"
  security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

printf '%s' "$IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64" | base64 -D > "${work_dir}/distribution.p12"
printf '%s' "$IOS_DISTRIBUTION_PROFILE_BASE64" | base64 -D > "${work_dir}/distribution.mobileprovision"
security cms -D -i "${work_dir}/distribution.mobileprovision" -o "${work_dir}/profile.plist"

profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "${work_dir}/profile.plist")"
profile_name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "${work_dir}/profile.plist")"
profile_team="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "${work_dir}/profile.plist")"
profile_app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "${work_dir}/profile.plist")"
if [[ "$profile_team" != "$team_id" || "$profile_app_id" != "${team_id}.${bundle_id}" ]]; then
  echo 'Profil Apple nie pasuje do zespołu lub identyfikatora Emma Staging.' >&2
  exit 1
fi

profiles_dir="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profiles_dir"
profile_path="${profiles_dir}/${profile_uuid}.mobileprovision"
cp "${work_dir}/distribution.mobileprovision" "$profile_path"

keychain_password="$(openssl rand -hex 20)"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "${work_dir}/distribution.p12" -k "$keychain_path" \
  -P "$IOS_DISTRIBUTION_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$keychain_password" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path"
security find-identity -v -p codesigning "$keychain_path"

archive_path="${work_dir}/Emma.xcarchive"
export_dir="${work_dir}/export"
export_options="${work_dir}/ExportOptions.plist"

xcodebuild archive \
  -project Emma.xcodeproj \
  -scheme Emma-Staging \
  -configuration Staging \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  CURRENT_PROJECT_VERSION="$GITHUB_RUN_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Apple Distribution' \
  EMMA_CI_PROVISIONING_PROFILE_SPECIFIER="$profile_name" \
  DEVELOPMENT_TEAM="$team_id"

plutil -create xml1 "$export_options"
/usr/libexec/PlistBuddy -c 'Add :method string app-store-connect' "$export_options"
/usr/libexec/PlistBuddy -c 'Add :destination string export' "$export_options"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "$export_options"
/usr/libexec/PlistBuddy -c "Add :teamID string $team_id" "$export_options"
/usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "$export_options"
/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:${bundle_id} string ${profile_name}" "$export_options"

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_dir" \
  -exportOptionsPlist "$export_options"

ipa_path="${export_dir}/Emma.ipa"
if [[ ! -f "$ipa_path" ]]; then
  echo 'Xcode nie wyeksportował Emma.ipa.' >&2
  exit 1
fi

mkdir -p "$(dirname "$api_key_path")"
printf '%s' "$ASC_PRIVATE_KEY_P8" > "$api_key_path"
chmod 600 "$api_key_path"
upload_log="${work_dir}/upload.log"
if ! xcrun altool --upload-app --type ios --file "$ipa_path" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee "$upload_log"; then
  echo 'Transporter nie zdołał wysłać IPA.' >&2
  exit 1
fi
if grep -Eq 'UPLOAD FAILED|Validation failed|Failed to upload package' "$upload_log"; then
  echo 'Apple odrzuciło IPA podczas walidacji.' >&2
  exit 1
fi

echo "Wysłano Emma Staging, build ${GITHUB_RUN_ID}, do App Store Connect."
