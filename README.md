# Hotel Booking Database

A MySQL database script for a sample hotel booking system. It creates hotel, room, guest, booking, payment, sightseeing, audit, guest-import, and vehicle data, along with triggers, views, and a stored procedure for booking operations and reporting.

The SQL file also demonstrates common queries, transaction control, CSV import/export workflows, and negative tests for trigger rules.

## Contents

- [Requirements](#requirements)
- [Setup](#setup)
- [Database schema](#database-schema)
- [Triggers and stored procedure](#triggers-and-stored-procedure)
- [Views](#views)
- [Sample data](#sample-data)
- [Usage examples](#usage-examples)
- [CSV workflows](#csv-workflows)
- [Notes and limitations](#notes-and-limitations)

## Requirements

- MySQL Server with support for InnoDB foreign keys, triggers, views, stored procedures, `SIGNAL`, and `GET DIAGNOSTICS`.
- A MySQL client such as MySQL Workbench or the `mysql` command-line client.

The script does not state a minimum MySQL version. Use a current MySQL 8.x release; the script includes `CHECK` constraints and diagnostics handling.

## Setup

> **Warning:** The script begins with `DROP DATABASE IF EXISTS hotels`. Running it deletes and recreates the `hotels` database, including any existing data in it.

### Run with the MySQL command-line client

Save the SQL dump locally, then run:

```sh
mysql -u YOUR_USER -p < "hotels(1).sql"
```

Enter the password when prompted. The script creates and selects the `hotels` database itself.

### Run with MySQL Workbench

Open the SQL file in Workbench and execute the full script against your MySQL server. The dump uses `DELIMITER` directives for trigger and procedure bodies, which Workbench supports.

After execution, select the `hotels` schema and query its tables or views.

## Database schema

The script creates the following tables:

| Table | Purpose and notable columns |
| --- | --- |
| `hotels` | Hotel name, destination, address, coordinates, base rate, and pickup/drop fees. |
| `room_types` | Unique room type names, tariff multipliers, and image filenames. |
| `rooms` | Rooms assigned to a hotel and room type; room numbers are unique and status is `Available` or `Booked`. |
| `guests` | Guest contact and identity details; full name is required and phone is unique. |
| `bookings` | Guest, room, dates, total amount, and status (`Booked`, `CheckedOut`, or `Cancelled`). Check-out must be later than check-in. |
| `payments` | Payments associated with a booking, including amount, method, and timestamp. |
| `sightseeing` | Sightseeing options and per-person prices associated with a hotel. |
| `audit_log` | Trigger-generated event type, reference ID, details, and timestamp. |
| `guest_import` | Staging table for guest rows before adding new guests to `guests`. |
| `cars` | Pickup/drop vehicle name, seat count, and fee multiplier. |

### Relationships

- A hotel has many rooms; each room references one hotel.
- A room type can be assigned to many rooms; each room references one room type.
- A guest can have many bookings; each booking references one guest.
- A room can appear in many bookings over time; each booking references one room.
- A booking can have many payments.
- A hotel can have many sightseeing entries.
- `v_car_tariff` combines every hotel with every car to calculate pickup and drop tariffs.

Foreign keys cascade deletion from guests to their bookings and from bookings to their payments. Other listed foreign keys do not specify cascading behavior.

## Triggers and stored procedure

Five triggers are defined:

- `trg_no_overlap` (before booking insert) rejects a new booking when its date range overlaps an existing booking with status `Booked` for the same room.
- `trg_mark_booked` (after booking insert) sets the room status to `Booked` and records a `BOOKING_CREATED` audit event.
- `trg_checkout` (after booking update) releases the room when a booking changes to `CheckedOut` or `Cancelled`, provided no booking for that room remains in `Booked` status. It also writes an audit event.
- `trg_guest_guard` (before guest delete) rejects deletion when the guest has a booking in `Booked` status.
- `trg_guest_deleted` (after guest delete) records a `GUEST_DELETED` audit event.

The stored procedure `sp_run_negative_tests()` runs two expected-to-fail actions inside exception handlers: deleting a guest with an active booking and inserting an overlapping booking. It reports the trigger error messages and lets the script continue.

## Views

- `v_available_rooms` lists rooms with hotel, destination, room type, room number, and calculated tariff (`base_rate * multiplier`). A room is excluded when it has an active `Booked` booking covering the current date.
- `v_booking_list` joins booking, guest, hotel, and room details and calculates total advance paid per booking from `payments`.
- `v_car_tariff` calculates pickup and drop tariffs for each hotel/car pair by multiplying the hotel's fee by the vehicle's multiplier.

## Sample data

The dump inserts:

- 10 hotels across listed Indian destinations.
- 3 room types: Standard, Deluxe, and Suite.
- 2 rooms per room type per hotel (60 rooms total), generated from hotel and type IDs.
- 20 sightseeing entries (2 per hotel).
- 8 initial guests.
- 8 initial bookings and 8 corresponding advance payments.
- 3 cars: a 4-seat sedan, 7-seat SUV, and 12-seat van.
- 10 rows in the guest import staging example.

It then marks bookings with check-out dates before `2026-11-21` as checked out. Some subsequent demo statements update guest 1's email, raise the Goa base rate by 10%, check out booking 3, delete guest 3, create and roll back sample transaction data, and import only guest rows whose phone is not already present. These statements mutate the seeded data when the full script runs.

## Usage examples

The dump includes runnable examples for filtering, joining, sorting, grouping, and reporting. For example, list bookings with guest, hotel, room type, and room details:

```sql
SELECT g.full_name, h.name AS hotel, h.destination, t.type_name,
       r.room_no, b.check_in, b.check_out
FROM bookings b
JOIN guests g     ON g.guest_id = b.guest_id
JOIN rooms r      ON r.room_id = b.room_id
JOIN hotels h     ON h.hotel_id = r.hotel_id
JOIN room_types t ON t.type_id = r.type_id;
```

See all booking details, including advance paid:

```sql
SELECT * FROM v_booking_list;
```

Find currently available rooms (as defined by the view):

```sql
SELECT * FROM v_available_rooms
ORDER BY hotel, room_no;
```

Summarize booking nights by month:

```sql
SELECT DATE_FORMAT(check_in, '%Y-%m') AS booking_month,
       COUNT(*) AS bookings,
       SUM(DATEDIFF(check_out, check_in)) AS room_nights
FROM bookings
WHERE status <> 'Cancelled'
GROUP BY booking_month
ORDER BY booking_month;
```

Show pickup/drop tariffs for a hotel:

```sql
SELECT *
FROM v_car_tariff
WHERE hotel_id = 1;
```

The SQL file also demonstrates `START TRANSACTION`, `COMMIT`, `ROLLBACK`, and `SAVEPOINT`.

## CSV workflows

### Export bookings

The dump shows the Workbench result-grid export workflow using:

```sql
SELECT * FROM v_booking_list;
```

A server-side `SELECT ... INTO OUTFILE` example is included but commented out. It requires a permitted MySQL `secure_file_priv` directory and server filesystem access.

### Import guests

The script creates `guest_import` and populates it with example rows. It then inserts only rows whose phone number is not already in `guests`.

For a real CSV, the dump includes a commented `LOAD DATA LOCAL INFILE` example. That route requires local-file loading to be enabled on both the server and client. The MySQL Workbench Table Data Import Wizard is also mentioned in the SQL comments.

## Notes and limitations

- The dump is a demonstration script, not an application. It contains no application code, authentication, or API.
- It is destructive to an existing `hotels` database because it drops and recreates that database.
- Seed booking statements use generated room and guest IDs and payment rows use booking IDs 1–8. Run the dump from its beginning against the freshly recreated database so these assumptions hold.
- The availability view checks date overlap against `CURDATE()`. The `rooms.status` column is also maintained by triggers, but the view does not use that status to determine availability.
- The overlap trigger checks inserts only. The dump does not define a corresponding trigger for updates to booking dates or rooms.
- The guest deletion guard prevents deleting a guest with a `Booked` booking; foreign-key cascade behavior is separately declared for guest bookings and booking payments.
- The sample data and date update use fixed dates, so results change as calendar time advances.
- The car tariff view calculates prices from the stored hotel pickup/drop fees and car multipliers; it does not store individual pickup or drop bookings.
- `SQL_SAFE_UPDATES` is disabled at the start and enabled again at the end for the current session.

## License

No license is specified in the SQL file.
