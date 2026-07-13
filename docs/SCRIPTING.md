# Custom Script Rules API

ClipShelf lets you write JavaScript functions that process clipboard content in real time. Scripts run inside a sandboxed `JSContext` (JavaScriptCore) — no network access, no filesystem access.

## The `process()` Function

Every script must define exactly one function:

```js
function process(content, bundleID) {
  // content  — the clipboard text (String)
  // bundleID — source app bundle ID (String | null)
  //
  // Return values:
  //   string  → replaces the clipboard content with this string
  //   null    → discards the item (not saved to history)
  //   (same)  → returning the original content = passthrough (no change)
}
```

### Parameters

| Name | Type | Description |
|---|---|---|
| `content` | `String` | The text content currently on the clipboard. |
| `bundleID` | `String \| null` | The bundle identifier of the app that produced the content (e.g. `"com.apple.Safari"`). May be `null` if unknown. |

### Return Values

| Return | Effect |
|---|---|
| A different `String` | The clipboard item is stored with the returned text. |
| The same `String` | Passthrough — the item is stored unchanged. |
| `null` | The item is discarded and not saved to history. |
| Anything else | Treated as passthrough. |

## Security Restrictions

- **Timeout**: Scripts must complete within **3 seconds**. If execution exceeds this limit, the result is discarded and the item passes through unchanged.
- **No timers**: `setTimeout` and `setInterval` are removed.
- **No I/O**: There is no access to `fetch`, `XMLHttpRequest`, the filesystem, or any network API.
- **No globals**: The script runs in a fresh `JSContext` for each invocation — no state persists between calls.

## Examples

### Format JSON

```js
function process(content, bundleID) {
  try {
    var obj = JSON.parse(content);
    return JSON.stringify(obj, null, 2);
  } catch (e) {
    return content; // not JSON, pass through
  }
}
```

### Extract Email Addresses

```js
function process(content, bundleID) {
  var emails = content.match(/[\w.+-]+@[\w-]+\.[\w.]+/g);
  if (emails && emails.length > 0) {
    return emails.join("\n");
  }
  return content;
}
```

### Discard Content from a Specific App

```js
function process(content, bundleID) {
  if (bundleID === "com.example.SensitiveApp") {
    return null; // discard
  }
  return content;
}
```

### Strip HTML Tags

```js
function process(content, bundleID) {
  return content.replace(/<[^>]*>/g, "");
}
```

### Prefix URL Copies with a Tag

```js
function process(content, bundleID) {
  if (/^https?:\/\//.test(content)) {
    return "[link] " + content;
  }
  return content;
}
```

## Adding a Script Rule

1. Open **Settings → Rules → Add Rule**.
2. Set the trigger (e.g. "All content" or "Content matches regex").
3. Under **Actions**, select **Custom Script**.
4. Paste your JavaScript in the script editor.
5. Click **Save**.

You can test your script using the **Test Rules** panel before saving.
