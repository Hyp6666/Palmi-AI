# Stability Checklist

Use this checklist after changes to chat, translation, streaming, history, or reasoning UI.

## Manual stress scenarios

1. Chat for 3 to 5 turns, switch to translation, immediately send a short message.
2. Start generation, rapidly expand and collapse `thinking` 10 times.
3. Send a message, tap stop, switch mode, and send again without waiting.
4. Open a long history session, scroll aggressively, expand `thinking`, then switch to another history item.

## Expected outcomes

- No freeze, crash, or permanent input lock.
- Send is accepted at most once per tap.
- Mode switch always ends in a stable draft and message list state.
- `thinking` can be toggled, but repeated taps are throttled instead of stalling the UI.
- Streaming text keeps updating, and final assistant message renders correctly after completion.

## Diagnostics to inspect

- `stability` logs for `action:*`, `blocked action:*`, and persistence checkpoints.
- Signposts for `Generation`, `ModeSwitchTransition`, `StopTransition`, `RestoreTransition`, and `PersistenceWrite`.
- Any persistence encode/write failure, generation cancellation, or engine warmup failure.

## Regression notes

- Streaming assistant content is intentionally plain text until generation finishes.
- `thinking` is intentionally collapsed by default while streaming.
- Interaction can be temporarily locked during mode switching, restoring, and stop transitions.
