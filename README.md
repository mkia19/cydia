# Legacy Cydia Repo on GitHub

A Cydia repo for old jailbroken iOS devices (iOS 3–9 era), hosted for free on GitHub Pages.
Every push to `main` builds the packages and publishes the repo with GitHub Actions. You don't
need Linux, `dpkg` or a Mac on your own machine.

## Layout

```
repo.conf                     repo name and description shown in Cydia
packages/<bundle-id>/         package source: DEBIAN/control + files laid out like the device's filesystem
debs/                         drop prebuilt .deb files here (they're published unchanged)
site/index.html               landing page with an "Add to Cydia" button
site/CydiaIcon.png            repo icon shown in Cydia's Sources list (64x64)
site/depictions/<bundle-id>/  package description page that Cydia shows
scripts/build-repo.sh         builds .debs and creates Packages, Packages.bz2, Packages.gz and Release
.github/workflows/            runs the build and deploys to GitHub Pages
```

## Setup (one time)

1. Create a **public** repository on GitHub and push these files to the `main` branch.
2. In the repo, open **Settings → Pages → Build and deployment → Source** and choose **GitHub Actions**.
3. Open the **Actions** tab and wait for "Build and publish Cydia repo" to finish (or click *Run workflow*).
4. Your repo is now at `https://<username>.github.io/<repo-name>/`. Open it in a browser to see the landing page.

## Important: HTTPS and very old iOS

`*.github.io` addresses are **HTTPS only**. Cydia on newer legacy firmwares (around iOS 7 and up) usually
handles that fine. **iOS 3–6 often can't**, because of old TLS support and expired root certificates.
To support those devices, use a custom domain served over plain HTTP:

1. Buy or use a domain/subdomain, e.g. `repo.example.com`, and add a DNS `CNAME` record pointing to
   `<username>.github.io`.
2. Put a file named `CNAME` (no extension) in the root of this repo containing just `repo.example.com`.
3. In **Settings → Pages**, enter the custom domain and **untick "Enforce HTTPS"**.
4. Push. The build sees `CNAME` and uses `http://repo.example.com` for all repo links.

The source to add in Cydia is then `http://repo.example.com/`.

## Adding a package

**From source** (scripts, config files, prebuilt binaries/dylibs):

1. Copy `packages/com.example.hellolegacy` to `packages/com.yourname.yourpackage`.
2. Edit `DEBIAN/control`. `Package` must match the folder name. Keep `Architecture: iphoneos-arm`.
   Raise `Version` with every update, or Cydia won't offer the update.
3. Put the files at the paths they should have on the device, e.g. `Library/MobileSubstrate/DynamicLibraries/MyTweak.dylib`
   and `MyTweak.plist`. (For a tweak, also add `mobilesubstrate` to `Depends`.)
4. Optionally add `DEBIAN/postinst` etc. Permissions are set by the build, so Windows is fine.
5. Copy `site/depictions/com.example.hellolegacy` for your package's description page and edit it.
6. Commit and push.

**Prebuilt .deb:** drop it into `debs/` and push. Make sure it was built with gzip compression
(`dpkg-deb -Zgzip`). Old iOS dpkg can't install xz- or zstd-compressed debs.

Remove the example package once you have your own.

## What the build does for legacy compatibility

- Builds debs with **gzip** compression and root ownership (`dpkg-deb --root-owner-group -Zgzip`)
- Publishes a flat repo with `Packages`, `Packages.bz2` (what old Cydia fetches) and `Packages.gz`
- Writes a `Release` file with `Architectures: iphoneos-arm` and MD5/SHA1/SHA256 checksums
- Removes Windows CRLF line endings from control files and maintainer scripts, and sets executable bits
- Builds depiction and landing pages with simple HTML/CSS that renders in iOS 3-era UIWebView

## Building locally (optional)

On Linux or WSL (Ubuntu):

```sh
sudo apt install dpkg-dev apt-utils bzip2
REPO_URL=http://localhost:8000 bash scripts/build-repo.sh
cd _site && python3 -m http.server 8000
```

## Removing the example

Delete `packages/com.example.hellolegacy` and `site/depictions/com.example.hellolegacy`, then push.
