# Health Assistant AI providers

S2Y exposes exactly two user-selectable AI providers in Health Assistant:

| Provider | Execution boundary | Health context | Failure behavior |
| --- | --- | --- | --- |
| Apple on-device | Apple Foundation Models on the current iPhone | Read locally from HealthKit | Never sends the question online; explains device or model readiness |
| Omer Online | `chat.s2y.us` through the authenticated Omer mobile API | Sent only for separately consented scopes | Reports the Omer failure; never presents a local mock response |

The app never changes providers automatically. Choosing on-device AI does not authorize an Omer request. Choosing Omer does not imply consent to every health-data scope.

Downloaded Phi/MLX models are not a supported runtime path. The earlier simulator containers, generated sample health values, model download screen, and bundled model metadata were removed because they could present synthetic output as a real analysis. Simulator testing verifies unavailable-state UX; Apple on-device inference must be tested on an eligible iPhone.

The provider selector, availability guidance, sharing consent ledger, and local/cloud conversation persistence are independent concerns. Changes to one boundary must not silently broaden another.
