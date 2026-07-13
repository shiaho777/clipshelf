# ClipShelf CloudKit Schema

Container: `iCloud.com.nicebro.ClipShelf`  
Database: Private  
Zone: `ClipboardHistory`

## Record type: `ClipboardItem`

| Field | Type | Notes |
|-------|------|--------|
| content | String | Plain text / path payload |
| type | String | `text`, `richText`, `image`, `fileURL` |
| timestamp | Date/Time | Item creation time |
| isPinned | Int64 | 0 / 1 |
| useCount | Int64 | |
| rtfData | Bytes | Optional |
| ocrText | String | Optional |
| imageHash | String | Optional |
| imageAsset | Asset | Optional image payload |

Record name = clipboard item UUID string.

Development schema is created on first write when the app runs against the Development environment with a signed build that includes the CloudKit entitlement.
