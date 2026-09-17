# Security

The supported scope of this fork is local audio capture, Apple Speech recognition, a loopback MLX service, and live captions. Keep the model service bound to loopback; it is not intended as a public authenticated server.

Dependencies and models are obtained during explicit setup. Review the selected model's provenance and license, keep dependencies updated deliberately, and do not enable remote-code execution for an unreviewed model.

Do not post audio, transcripts, diagnostic logs, tokens, private keys, or signing material in public issues. If a vulnerability affects this fork, use the repository host's private security-reporting feature when enabled. If no private contact is configured, open an issue requesting a private contact without including exploit details or private data. Do not send a fork-specific report to the upstream author by default.

The repository does not distribute credentials. The CI artifact check fails on common credential/private-key patterns and reports only affected file paths. This check is a guard, not a guarantee that every secret format is recognized. Review the source diff and release contents before publication.
