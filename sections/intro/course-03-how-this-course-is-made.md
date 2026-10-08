# How This Course Is Made

You will trust a course more when you know how it is built. This page tells you how the content is written and checked, who is behind it, and how you can help make it better.

## How the content is written

- **One version.** Everything is built and checked on **Istio 1.30.5**. When a page says how Istio behaves, it means that version.
- **Real sources.** Facts are checked against the official Istio documentation, in particular the traffic management concepts page and the API reference for each object. Each page explains everything you need on the page itself, so you never have to leave the course to look something up.
- **Real output.** When a page shows command output, it comes from a real run. If the output is shortened, the page says so. If there was no real run to copy from, the page describes the result in words instead of making up output.
- **Graders check behaviour.** Every graded lab sends real traffic and reads the proxy's own configuration. An object that exists but does nothing does not pass. Each lab also has a reference solution that is run against its own grader, so the grader is known to accept a correct answer.
- **Plain English.** The pages are written for people who are not native English speakers and have no university degree. Words are written out in full, and each new term gets a short explanation the first time it appears.
- **Written with AI help.** Large parts of this course are drafted and edited with the help of AI tools. A maintainer reviews every change before it is published, and the technical checks above apply to all content, however it was written.

## Mission crew

**Core maintainer**

- **Paris Nakita Kejser** ([@parisnakitakejser](https://github.com/parisnakitakejser))

**Everyone who has helped**

Every person who has changed the course is listed on the GitHub contributors page:
[github.com/astrona-io/ATS014/graphs/contributors](https://github.com/astrona-io/ATS014/graphs/contributors)

## Found a mistake? Report it

If a command fails, a page says something wrong, or a lab grades a correct answer as wrong, please tell us. Every report makes the course better for the next astronaut.

1. Open a new issue on GitHub: [github.com/astrona-io/ATS014/issues](https://github.com/astrona-io/ATS014/issues).
2. Say which page or lab it is (the file path is the easiest, for example `sections/section-010/module-01/labs/lab-01`).
3. Paste the command you ran and what you saw. Leave out passwords, tokens or anything else private.
4. Say what you expected to happen instead.

Want to fix it yourself? Pull requests are welcome on the same repository.

## License

The course is published under the [Apache License 2.0](https://github.com/astrona-io/ATS014/blob/main/LICENSE).
