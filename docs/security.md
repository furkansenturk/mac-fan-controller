# Security

Controlling fans means writing to the SMC, and macOS allows that only for root. Fan Controller therefore installs a small helper that runs as root. This page explains what that helper can do and how it is protected.

## What runs as root

Only `FanHelper`, whose source is two files in [`Helper/`](../Helper). It:

- accepts exactly the four calls in [`FanHelperProtocol`](../Packages/FanKit/Sources/FanXPC/FanHelperProtocol.swift): set a fan's speed, return a fan to automatic, report its version, and exit for an update (after returning every fan to automatic)
- clamps every requested speed to the fan's own minimum and maximum, and refuses the request when the speed isn't a number, the fan doesn't exist or its range can't be read (see [`FanLimits`](../Packages/FanKit/Sources/SMCKit/FanLimits.swift))
- writes only the fan mode key (`F<n>Md`) and the target speed key (`F<n>Tg`)
- doesn't read files, open network connections or run other programs

Everything else, including all reading and the whole UI, runs as the logged-in user.

## How it is installed

The helper is registered with `SMAppService.daemon(plistName:)`, the current API for launch daemons. Registration needs the user's approval in **System Settings › General › Login Items**, and the user can turn the helper off there at any time.

## Who can talk to it

The helper listens on the Mach service `com.furkansenturk.FanController.Helper`. Before it handles any message, it calls `NSXPCConnection.setCodeSigningRequirement(_:)` with this requirement:

```
anchor apple generic
and identifier "com.furkansenturk.FanController"
and certificate leaf[subject.OU] = "<team ID>"
and !entitlement["com.apple.security.get-task-allow"]   (Release builds only)
```

The system checks this requirement for every message, so another process, even one running as the same user, can't drive the fans. A helper built without a team ID rejects every connection.

The last line refuses a debuggable app, which other processes could inject code into and use to reach the helper. Release builds are signed without `get-task-allow` (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS` is off in `Base.xcconfig`); Debug builds keep it so they can be debugged, and their helper doesn't check for it.

## Failing safe

The helper returns every fan to automatic mode when:

- the app's connection is invalidated, because the app quit or crashed
- `launchd` sends `SIGTERM`, for example when the helper is turned off or the Mac shuts down
- the app asks it to exit after an update; it then refuses further writes until it has exited
- it starts, before handling any request

The last case covers a crash: nothing runs in a crashing process, so a fan may stay at its last target speed until the helper starts again. The app sends commands continuously, so `launchd` starts the helper again right away, and it first returns every fan to automatic. The SMC's own thermal protection still applies, and requested speeds are always clamped to the fan's minimum and maximum, so the helper can never set a speed the hardware doesn't allow.

## Reporting a vulnerability

See [SECURITY.md](../SECURITY.md).
