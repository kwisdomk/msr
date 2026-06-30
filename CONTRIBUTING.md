# Contributing

Thanks for helping improve Mr. Roboto.

Mr. Roboto is a portable media downloader powered by yt-dlp and FFmpeg. The project is maintained with a focus on small, reviewable changes and accurate documentation.

## Pull request guidelines

Please keep pull requests focused.

Good PRs usually do one thing:

- Fix one bug
- Add one small feature
- Improve one area of documentation
- Add or update one test checklist

Avoid mixing unrelated changes in the same PR.

## Documentation rules

Documentation should describe real behavior in the current codebase.

Please avoid:

- Large generated documentation dumps
- Roadmaps presented as completed features
- Unsupported platform claims
- Marketing-style wording
- Repeating the same information across multiple files

The README should remain the main source of truth.

## Runtime behavior

Do not change runtime behavior unless the PR clearly says so.

If a PR changes how Mr. Roboto runs, downloads files, handles paths, uses cookies, or resumes downloads, document that clearly in the PR description.

## Platform support

Current baseline:

- Windows: stable
- Linux: planned beta support

Linux documentation should only be added on a branch where `roboto.sh` exists.

## Testing notes

For code changes, include manual test notes:

- Operating system tested
- Shell or PowerShell version
- Command used
- Expected result
- Actual result
- Relevant error output or logs, if any

## Review expectations

Maintainers may request changes if a PR:

- Mixes unrelated changes
- Updates documentation without matching code behavior
- Changes Windows behavior without clear explanation
- Adds large generated documents
- Does not include enough test notes
