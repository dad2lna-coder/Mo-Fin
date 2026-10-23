# MoFin for Roku

Side-loadable SceneGraph channel. It is not the Flutter app. The zip on the
`latest` GitHub release has `manifest` at the root.

## Developer mode

1. On the Roku, press Home three times, then Up twice, then Right, Left, Right, Left, Right.
2. Note the IP address, enable the installer, and set a developer password.
3. Reboot if requested.

## Side-load

1. Download `Mo-Fin-roku.zip` from the `latest` release.
2. On a computer, open `http://<roku-ip>` and sign in with `rokudev` and the developer password.
3. Under Install, upload the zip. The **MoFin** channel appears at the end of the home screen.

Or via `curl`:

```bash
curl -f -u rokudev:PASSWORD --anyauth \
  -F "mysubmit=Install" \
  -F "archive=@Mo-Fin-roku.zip" \
  http://<roku-ip>/plugin_install
```

The default channel source template is `https://your-server/mofin/free/`
(`playlist.m3u`, `guide.xml`, and `rec/`). Change it from Settings on the
channel. The server certificate must be trusted by the Roku.
