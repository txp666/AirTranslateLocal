# Changes

## Unreleased — AirTranslate Local

- Focus the application on Apple Speech recognition, local MLX translation, and live/floating captions.
- Remove cloud-provider configuration, translated speech, and transcript history from the local edition.
- Share accepted translation results between the workspace and floating captions; fit caption tails to the actual window width and font.
- Pair each partial translation with its completed source segment and restore start readiness after a cancelled connection check.
- Provide explicit local runtime/model setup, offline model startup, and app-owned process cleanup.
- Recover pip after interrupted environment creation and report incompatible explicit Python overrides before installing elsewhere.
- Replace upstream download/marketing material with local installation, privacy, contribution, and packaging documentation.
- Verify fork artifacts without publishing releases or depending on upstream release tags.

The source is derived from himomohi's AirTranslate. Original notices are preserved in [NOTICE](NOTICE); the repository's Git history retains the upstream development history. This entry is not an announcement that a new binary release has been published.
