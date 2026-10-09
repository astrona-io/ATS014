# Capstone: Combine Timeouts, Retries, Circuit Breaking And Outlier Detection

This is the integration lab for the resilience section. Four features act on one service at the same time: a timeout and a retry policy that differ between reads and writes, a connection pool that rejects work the client cannot do quickly (circuit breaking), outlier detection that ejects an endpoint which keeps failing, and locality load balancing on top.

The features affect each other, and that is the point of the lab. Retries are extra concurrent requests sent to a connection pool that may already be full. Retries also hide from the client the failures that outlier detection needs to see. And a locality setting without outlier detection does nothing at all.

There is no step-by-step guide until you have tried it. Work from the specification in `question.md`.

## Launching the Lab

Run the following command in your terminal to start the `kind` Kubernetes cluster:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-040/capstone/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-040/capstone/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-040
```
