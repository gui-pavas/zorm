# Transactions

zorm exposes transaction primitives through `Driver`.

## API

- `beginTransaction() -> Transaction`
- `Transaction.commit()`
- `Transaction.rollback()`

## Example

```zig
var tx = try driver.beginTransaction();
errdefer tx.rollback() catch {};

try driver.execute("UPDATE accounts SET balance = balance - 100 WHERE id = 1");
try driver.execute("UPDATE accounts SET balance = balance + 100 WHERE id = 2");

try tx.commit();
```

## Behavior Notes

- `beginTransaction()` sends `BEGIN`.
- `commit()` sends `COMMIT`.
- `rollback()` sends `ROLLBACK`.
- `commit()` and `rollback()` return `error.TransactionAlreadyClosed` if the transaction was already completed.
