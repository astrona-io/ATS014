# Redirect, Rewrite And Change Headers Of A Request

This graded lab is about what a matched `VirtualService` rule can do besides choosing a destination. You answer a request with a redirect, rewrite its path, set and remove headers, and answer a browser's CORS (Cross-Origin Resource Sharing) preflight request. The application itself does not change.

## Launching the Lab
Run this command in your terminal to start the `kind` Kubernetes cluster:
```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-02
```
