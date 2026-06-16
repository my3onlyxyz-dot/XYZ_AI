#!/bin/bash
# Setup Flutter project di Termux + push ke GitHub

echo "=== Sahrul Control - Setup Script ==="

# 1. Cek Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter belum terinstall di Termux"
    echo "Install dulu via proot-distro Ubuntu:"
    echo "  proot-distro login ubuntu"
    echo "  apt install flutter"
    exit 1
fi

# 2. Get dependencies
echo "📦 Install dependencies..."
flutter pub get

# 3. Build APK
echo "🔨 Build APK (release)..."
flutter build apk --release

echo ""
echo "✅ APK tersedia di: build/app/outputs/flutter-apk/app-release.apk"
echo ""

# 4. Push ke GitHub (opsional)
read -p "Push ke GitHub? (y/n): " push
if [ "$push" == "y" ]; then
    read -p "Masukkan GitHub repo URL: " repo_url
    git init
    git add .
    git commit -m "feat: initial Sahrul Control app"
    git branch -M main
    git remote add origin "$repo_url"
    git push -u origin main
    echo "✅ Berhasil push ke GitHub!"
fi
