# Canonical tombstone fixture correction

Frozen spec-test commit: `6a5583f`. The server owner reported the first implementation run (handle 16253, exit 1) as six passes and one fixture failure: setting `disabled_at` without `disabled_reason` violated the existing `accounts_check1` constraint before the HTTP assertion executed. This receipt preserves the reported result; it is not a copy of the original raw log. The owner reused `workspace-library-discovery-green.log` for the later successful run, so that raw intermediate failure log is not retained.

The parent independently read `sql/003_identity.sql`: `(disabled_at IS NULL) = (disabled_reason IS NULL)`, allowed reasons include `account-delete`, and a non-null `tombstoned_at` requires that reason. WD02 and the plan change log were clarified. The exact fixture SQL diff was shown in user-facing commentary before authorization to edit:

```diff
- SET disabled_at=clock_timestamp(),auth_epoch=auth_epoch+1
+ SET disabled_at=clock_timestamp(),disabled_reason='account-delete',tombstoned_at=clock_timestamp(),auth_epoch=auth_epoch+1
```

The schema and the HTTP-401 assertions were not changed. The owner then reported seven actual HTTP/PostgreSQL passes (handle 18003, exit 0); the parent inspected that green log and the complete 60-test service result. The initial missing-route seven-failure log remains separately retained.
