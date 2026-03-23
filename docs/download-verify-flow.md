# gg_updater: Download + Checksum Verify Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  USER TAPS "Download"                                                             │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  download(url, version, sha256Checksum, sha1Checksum)                             │
│  url = _info.downloadUrl  (e.g. "/files/app.apk" or "https://...")                 │
│  expected = sha256 ?? sha1, lowercased, trimmed                                    │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌────────────────┴────────────────┐
                    │  file (update.apk) exists?       │
                    └────────────────┬────────────────┘
                         │                    │
                        YES                   NO
                         │                    │
                         ▼                    │
            ┌────────────────────────┐        │
            │ CACHE HIT PATH         │        │
            │ Verify checksum        │        │
            └────────────┬───────────┘        │
                         │                   │
              ┌──────────┴──────────┐        │
              │ ok?                 │        │
              └──────────┬──────────┘        │
                   │           │              │
                  YES         NO              │
                   │           │              │
                   │           ▼              │
                   │   _verifyChecksum        │
                   │   DELETES file           │
                   │   return null            │
                   │   (fall thru to          │
                   │    download below)      │
                   ▼           │              │
            Yield complete     │              │
            (Install now)      │              │
            RETURN             │              │
                               └──────────────┼──────────┐
                                              │          │
                                              ▼          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  FRESH / RESUME DOWNLOAD                                                          │
│  dio.download(url, partialFile or chunkFile)                                      │
│  → writes to update.apk.partial (or .chunk when resuming)                         │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  On complete: partialFile.rename(file.path)   ← update.apk.partial → update.apk │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  expected != null?  →  _verifyChecksum(file, expected, useSha256)                 │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                         ┌────────────┴────────────┐
                         │ result.ok?              │
                         └────────────┬────────────┘
                              │              │
                             YES            NO (MISMATCH)
                              │              │
                              │              ▼
                              │   ┌──────────────────────────────────────┐
                              │   │ _verifyChecksum DELETES file          │
                              │   │ _emit(Progress with error)            │
                              │   │ _cleanup()                            │
                              │   │ RETURN  ← User sees "Retry"            │
                              │   └──────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────────┐
                    │ _emit(complete)      │
                    │ filePath = path      │
                    │ _cleanup()           │
                    │ User sees Install    │
                    └──────────────────────┘
```

## Key files

| Path | Purpose |
|------|---------|
| `ota_updates/<version>/update.apk` | Final APK (after rename) |
| `ota_updates/<version>/update.apk.partial` | During download |
| `ota_updates/<version>/update.apk.chunk` | Resume: new bytes only |

## Potential problem: download URL

```
App gets UpdateInfo from: GET {rootHost}/api/method/...check_update
                         → { download_url: "/files/app.apk", sha1: "abc..." }

UI calls: service.download(_info.downloadUrl, ...)
          → download("/files/app.apk", ...)

Dio: baseUrl = rootHost (e.g. http://178.236.185.133:8001)
     download("/files/app.apk", targetPath)

     Dio resolves: baseUrl + path  →  http://178.236.185.133:8001/files/app.apk
     OR: if path is treated as absolute from root, same result.
```

If `download_url` is relative and the app's Dio has no `baseUrl`, or a different one, the download could hit the wrong URL → different file → hash mismatch.
