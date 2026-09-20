# Slop Guard

**Bring your engineering guidelines into every code review.**

Slop Guard is a code-review bot that checks whether a change follows defined engineering guidelines. It looks for missing behavior tests, untested failure cases, mixed responsibilities, and unnecessary abstractions, then provides feedback on the relevant code.

## Why use it?

**A passing build can still leave important review questions unanswered.** A test may run the changed code without checking the new behavior. A new class may add complexity without solving a current problem. These are easy to miss when a PR looks complete.

Slop Guard checks changes against your engineering guidelines and brings those concerns into the review. Each finding points to the relevant code, explains which guideline is at risk, and suggests a correction.

## How is it different from an LLM review bot?

An open-ended LLM reviewer reads a change and writes a review. Slop Guard follows a different division of work: **code identifies what to inspect, Jev judges it, and explicit rules decide what to report.**

Slop Guard identifies candidate code and tests, then asks Jev focused questions such as **“Does this test assert the behavior the PR promises?”** Jev returns numeric judgments. Slop Guard combines those answers using configured thresholds and creates comments from predefined messages, tied to validated source locations. Uncertain answers or missing evidence are reported as inconclusive.

This design supports three priorities:

- **Speed:** Jev answers focused questions without generating review text, and related questions can be answered together.
- **Cost:** Jev charges for input tokens with no output-token charge. Slop Guard builds the review comments itself.
- **Consistency:** The same questions, thresholds, and reporting rules apply to each change. You can test those checks against known examples before changing them.

Slop Guard currently makes multiple requests per review and has not benchmarked speed or cost against other bots. Consistent rules make the process repeatable; model judgments can still vary or be wrong.

This follows the article's [“Code enumerates, Jev judges” approach](https://tjklug.com/posts/typesafe-jev-slopcheck/), using [Jev's structured decision model](https://typesafe.ai/blog/introducing-system-one-models-and-jev).

## Example: a passing test that misses the feature

A payment API already supports cancellation. A PR adds a requirement: **record when the payment was cancelled**, so support can trace what happened.

```diff
 class CancelPayment
   def call(payment)
     payment.state = 'cancelled'
+    payment.cancelled_at = Time.current
     Command.save(payment)
   end
 end
```

The new test runs the service and checks that it saves the payment:

```ruby
it 'records the cancellation time' do
  allow(Command).to receive(:save)

  CancelPayment.new.call(payment)

  expect(Command).to have_received(:save).with(payment)
end
```

**Delete the new line and the test still passes.** It checks that the same object was saved, but never checks its cancellation time. The feature is unprotected even though the test runs the real service.

Slop Guard checks two things: does the test run the real cancellation code, and does it assert the required timestamp? Here, the test runs the code but never checks the timestamp—the combination its rules are designed to flag.

An illustrative finding using the bot's configured wording:

> The inspected tests do not demonstrate this changed behavior.
>
> Add a production-path assertion of the expected result, or identify the existing test that provides it.

The test should check the values passed to persistence. With a payment whose `cancelled_at` starts as `nil`:

```ruby
it 'records the cancellation time' do
  freeze_time do
    allow(Command).to receive(:save)

    CancelPayment.new.call(payment)

    expect(Command).to have_received(:save).with(
      have_attributes(state: 'cancelled', cancelled_at: Time.current)
    )
  end
end
```

Now removing the timestamp assignment makes the test fail.

## Example: an abstraction without a present need

Another PR proposes a gateway to “support more cancellation flows later.” The application already has a payment adapter that isolates the external provider:

```diff
 class CancelPayment
   def call(payment)
-    Adapter.payments.cancel(payment_id: payment.external_id)
+    PaymentCancellationGateway.new.cancel(payment)
   end
 end
+
+class PaymentCancellationGateway
+  def cancel(payment)
+    Adapter.payments.cancel(payment_id: payment.external_id)
+  end
+end
```

The new class forwards the same call. In this example, it has one caller, adds no validation or error handling, and serves no current requirement beyond the existing adapter. A reader now has to open another class to understand the same operation.

Slop Guard's abstraction check asks whether the extra layer has a demonstrated purpose, including dependency isolation and framework requirements. An illustrative finding:

> The new abstraction has no demonstrated purpose in the supplied context.
>
> Use the existing concrete component, or explain and demonstrate the present constraint served by this layer.

The suggested simplification is to keep calling `Adapter.payments` directly. The adapter itself has a purpose: separating the service from the payment provider. A second layer may become useful when there is actual shared behavior or another concrete constraint.

Both examples are simplified API scenarios illustrating the checks, not recorded Jev results.

## Get started

- [Try a local review](docs/getting-started.md)
- [Review your own repository](docs/local-repository-review.md)
- [Install and host the GitHub App](docs/github-app.md)

For details, see the [review guidelines](docs/guidelines.md), [evaluation guide](docs/evaluation.md), [benchmarks](docs/evaluation-benchmark.md), and [CI documentation](docs/ci.md).

**Status:** experimental and advisory. Current support is limited to small Ruby/RSpec projects. Review accuracy and live GitHub delivery still need validation; see the [recorded evaluation results](docs/verification/threshold-calibration.md).

Inspired by TJ Klug's [slopcheck](https://tjklug.com/posts/typesafe-jev-slopcheck/) approach to combining focused model judgments with decisions made in code.
