# Google Play Games Flags

Small unofficial helper for launching Google Play Games on PC with local Phenotype flag overrides.

This is unsupported and uses internal Google Play Games flags. It does not modify or redistribute Google Play Games files, but using internal flags may conflict with Google's terms. Use at your own risk.

The included `flags.json` is for fixing the missing hide-sidebar button by enabling the sidebar collapsibility flags.

Run `Encrypt-GooglePlayGamesFlags.ps1` with `flags.json` in the same folder. The script encrypts the JSON, places the encrypted flags file in the Google Play Games install folder, and creates:

```text
Google Play Games - Flags.lnk
```

That shortcut points directly at the Google Play Games `Service.exe` and starts it with the `/flags` option:

```text
Service.exe /flags "...\flags.encrypted"
```

The shortcut launches Google Play Games with the encrypted version of `flags.json`, so the service applies those overrides during startup.

## Finding more flags

Google does not provide a public, stable list of Google Play Games Phenotype flags. Names can change between versions.

On a default install, flag names are in:

```text
C:\Program Files\Google\Play Games\current\service\Phenotype.dll
```

Inspecting Google binaries may be restricted by Google's terms. Only use extra flags if you accept that risk.

The script only needs elevated privileges if it cannot write the encrypted flags file into the Google Play Games folder. In that case, it relaunches itself as administrator.
