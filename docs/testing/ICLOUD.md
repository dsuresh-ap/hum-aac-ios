# Checking iCloud sync records (for developers)

Hum's app no longer shows these steps or raw sync errors to parents (BUGS.md, HUM-023). To look at what a
device has synced:

1. Open the CloudKit Console (icloud.developer.apple.com) → `iCloud.dhananjaysuresh.hum-aac`.
2. Pick the **Development** environment for Xcode builds; App Store and TestFlight builds use **Production**.
3. Choose the Private Database, zone `com.apple.coredata.cloudkit.zone`. Sign in with the same Apple Account
   as the device ("Act as iCloud Account").
4. Record types are `CD_Board` and `CD_Tile`. To list them, add a QUERYABLE index on `recordName` under
   Schema → Indexes, then query.

The Public database is always empty: Hum never uses it.

Raw sync errors are in the device log: filter Console.app for the Hum process and `CloudKit` or
`NSCloudKitMirroringDelegate`. `Persistence.iCloudError` holds the error that turned iCloud off at launch.
