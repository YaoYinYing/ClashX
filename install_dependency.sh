#!/bin/bash
set -e

required_ruby_version="2.7.0"
recommended_ruby_version="3.2.4"

if ! command -v ruby >/dev/null 2>&1; then
  ruby_version="not installed"
elif ruby_version="$(ruby -e 'print RUBY_VERSION' 2>/dev/null)"; then
  :
else
  ruby_version="unavailable"
fi

if [[ "$ruby_version" == "not installed" || "$ruby_version" == "unavailable" ]] || \
   ! ruby -e 'exit Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.7.0") ? 0 : 1' >/dev/null 2>&1; then
  cat <<EOF
SmartX requires Ruby >= ${required_ruby_version} for Bundler dependencies.
Your Ruby is: ${ruby_version}
macOS system Ruby 2.6 is not supported.
Install a project Ruby, for example:
  brew install rbenv ruby-build
  rbenv install ${recommended_ruby_version}
  rbenv local ${recommended_ruby_version}
  gem install bundler
Then rerun:
  bundle install
  bash install_dependency.sh
EOF
  exit 1
fi

echo "Build Clash core"

cd ClashX/goClash
python3 build_clash_universal.py
cd ../..

echo "Pod install"
bundle install --jobs 4
bundle exec pod install
echo "delete old files"
rm -f ./ClashX/Resources/Country.mmdb
rm -rf ./ClashX/Resources/dashboard
rm -f GeoLite2-Country.*
echo "install mmdb"
curl -LO https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb
gzip Country.mmdb
mv Country.mmdb.gz ./ClashX/Resources/Country.mmdb.gz
echo "install dashboard"
cd ClashX/Resources
git clone -b gh-pages https://github.com/MetaCubeX/Yacd-meta.git dashboard
cd dashboard
rm -rf -- ./*.webmanifest ./*.js ./CNAME ./.git

# Yacd-meta embeds its default top-left logo as a base64 CSS background image
# inside the built assets, so there is no standalone upstream file to replace.
# SmartX overrides that logo after each clone to avoid editing upstream build
# artifacts manually; Resources/dashboard is recreated by this script, so manual
# edits under ClashX/Resources/dashboard are not persistent.
# The copied smartx-icon.png lives next to the patched CSS file so the relative
# URL stays stable inside the dashboard asset directory.
echo "apply SmartX dashboard branding"
dashboard_logo_source="../icon-transparent.png"
dashboard_css_file="$(find . -type f -name '*.css' -exec grep -l '_logo_meta_' {} + 2>/dev/null | head -n 1)"

if [[ ! -f "$dashboard_logo_source" ]]; then
  echo "warning: SmartX dashboard logo source not found at $dashboard_logo_source"
elif [[ -z "$dashboard_css_file" ]]; then
  echo "warning: no dashboard CSS file containing _logo_meta_ found under $(pwd)"
else
  dashboard_css_dir="$(dirname "$dashboard_css_file")"
  dashboard_logo_target="$dashboard_css_dir/smartx-icon.png"

  cp "$dashboard_logo_source" "$dashboard_logo_target"
  cat <<'EOF' >> "$dashboard_css_file"

/* SmartX dashboard branding override:
   Yacd-meta embeds the default logo as a base64 CSS background image.
   SmartX overrides that generated CSS after clone instead of manually editing
   upstream build artifacts, and copies smartx-icon.png next to this CSS file
   so the relative URL remains stable across dashboard rebuilds. */
[class*="_logo_meta_"]{
background-image:url("./smartx-icon.png")!important;
background-size:contain!important;
background-repeat:no-repeat!important;
background-position:center!important;
}
EOF

  echo "SmartX dashboard logo override applied: $(pwd)/$dashboard_css_file"
  echo "SmartX dashboard logo asset copied: $(pwd)/$dashboard_logo_target"
fi
