# Contributing

This fork focuses on local speech recognition, MLX translation, and readable live/floating captions. Keep user controls limited to the current task. Do not reintroduce hosted providers, API-key settings, dubbing, or a transcript library as incidental dependencies.

## Development

Use an Apple Silicon Mac with macOS 26+ and Swift 6.2+. For model-backed manual checks, follow [local setup](docs/local-mlx.md); unit tests must not require a model download or external credentials.

```bash
swift test
./script/verify_packaging_permissions.sh
./script/build_and_run.sh --build
```

For changes to translation presentation, check both the main workspace and floating window, including streaming revisions, narrow windows, Chinese/Japanese text, and larger caption sizes. For model process changes, check startup failure, cancellation, normal exit, and forced app exit.

Keep generated apps, models, Python environments, logs, credentials, and personal file paths out of commits. Include only changes related to the intended fix. Preserve the original Apache license and attribution.

## Pull requests and distribution

Explain the concrete problem, the resulting behavior, and the checks you ran. Distinguish automated tests from real audio/model validation. Run release packaging checks when changing scripts, resources, identity, or entitlements.

The checkout may still have the upstream project as `origin`. Inspect `git remote -v` and choose your own fork before pushing. No build or CI script publishes a release. Do not treat an upstream download link as a download for this local edition.
