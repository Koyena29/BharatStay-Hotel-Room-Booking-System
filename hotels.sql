SET SQL_SAFE_UPDATES = 0;

DROP DATABASE IF EXISTS hotels;
CREATE DATABASE hotels;
USE hotels;


CREATE TABLE hotels (
  hotel_id    INT PRIMARY KEY AUTO_INCREMENT,
  name        VARCHAR(100),
  destination VARCHAR(50),
  place       VARCHAR(100),
  address     VARCHAR(200),
  lat         DECIMAL(9,6),
  lng         DECIMAL(9,6),
  base_rate   INT,
  pickup_fee  INT,
  drop_fee    INT
);

CREATE TABLE room_types (
  type_id    INT PRIMARY KEY AUTO_INCREMENT,
  type_name  VARCHAR(50) UNIQUE,
  multiplier DECIMAL(3,1),
  image      VARCHAR(100)
);

CREATE TABLE rooms (
  room_id  INT PRIMARY KEY AUTO_INCREMENT,
  hotel_id INT,
  type_id  INT,
  room_no  VARCHAR(10) UNIQUE,
  status   ENUM('Available','Booked') DEFAULT 'Available',
  FOREIGN KEY (hotel_id) REFERENCES hotels(hotel_id),
  FOREIGN KEY (type_id)  REFERENCES room_types(type_id)
);

CREATE TABLE guests (
  guest_id  INT PRIMARY KEY AUTO_INCREMENT,
  full_name VARCHAR(100) NOT NULL,
  phone     VARCHAR(20) UNIQUE,
  email     VARCHAR(100),
  city      VARCHAR(50),
  id_proof  VARCHAR(50)
);

CREATE TABLE bookings (
  booking_id   INT PRIMARY KEY AUTO_INCREMENT,
  guest_id     INT,
  room_id      INT,
  check_in     DATE,
  check_out    DATE,
  total_amount INT,
  status       ENUM('Booked','CheckedOut','Cancelled') DEFAULT 'Booked',
  CHECK (check_out > check_in),
  FOREIGN KEY (guest_id) REFERENCES guests(guest_id) ON DELETE CASCADE,
  FOREIGN KEY (room_id)  REFERENCES rooms(room_id)
);

CREATE TABLE payments (
  payment_id INT PRIMARY KEY AUTO_INCREMENT,
  booking_id INT,
  amount     INT,
  method     VARCHAR(20),
  paid_on    DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE
);

CREATE TABLE sightseeing (
  sight_id         INT PRIMARY KEY AUTO_INCREMENT,
  hotel_id         INT,
  place            VARCHAR(100),
  price_per_person INT,
  FOREIGN KEY (hotel_id) REFERENCES hotels(hotel_id)
);

CREATE TABLE audit_log (
  log_id     INT PRIMARY KEY AUTO_INCREMENT,
  event_type VARCHAR(50),
  ref_id     INT,
  details    VARCHAR(255),
  logged_at  DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================================
-- TRIGGERS  (DELIMITER lets us use ; inside the trigger body)
-- =====================================================================
DELIMITER $$

-- Trigger 1 (BEFORE INSERT): block overlapping dates for the same room
CREATE TRIGGER trg_no_overlap BEFORE INSERT ON bookings
FOR EACH ROW
BEGIN
  IF EXISTS (SELECT 1 FROM bookings b
             WHERE b.room_id = NEW.room_id
               AND b.status = 'Booked'
               AND NEW.check_in < b.check_out
               AND NEW.check_out > b.check_in) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room already booked for these dates';
  END IF;
END$$

-- Trigger 2 (AFTER INSERT): mark room as Booked + write audit log
CREATE TRIGGER trg_mark_booked AFTER INSERT ON bookings
FOR EACH ROW
BEGIN
  UPDATE rooms SET status = 'Booked' WHERE room_id = NEW.room_id;
  INSERT INTO audit_log(event_type, ref_id, details)
  VALUES ('BOOKING_CREATED', NEW.booking_id,
          CONCAT('Room ', NEW.room_id, ' booked for guest ', NEW.guest_id));
END$$

-- Trigger 3 (AFTER UPDATE): on check-out / cancel, free the room
CREATE TRIGGER trg_checkout AFTER UPDATE ON bookings
FOR EACH ROW
BEGIN
  IF NEW.status IN ('CheckedOut','Cancelled') AND OLD.status <> NEW.status THEN
    UPDATE rooms SET status = 'Available'
    WHERE room_id = NEW.room_id
      AND NOT EXISTS (SELECT 1 FROM bookings
                      WHERE room_id = NEW.room_id AND status = 'Booked');
    INSERT INTO audit_log(event_type, ref_id, details)
    VALUES (CONCAT('BOOKING_', UPPER(NEW.status)), NEW.booking_id,
            CONCAT('Room ', NEW.room_id, ' released'));
  END IF;
END$$

-- Trigger 4 (BEFORE DELETE): a guest can be deleted only AFTER check-out
CREATE TRIGGER trg_guest_guard BEFORE DELETE ON guests
FOR EACH ROW
BEGIN
  IF EXISTS (SELECT 1 FROM bookings
             WHERE guest_id = OLD.guest_id AND status = 'Booked') THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Guest has an active booking - check out first';
  END IF;
END$$

-- Trigger 5 (AFTER DELETE): log deleted guests
CREATE TRIGGER trg_guest_deleted AFTER DELETE ON guests
FOR EACH ROW
BEGIN
  INSERT INTO audit_log(event_type, ref_id, details)
  VALUES ('GUEST_DELETED', OLD.guest_id, OLD.full_name);
END$$

DELIMITER ;

-- =====================================================================
-- ## 2. INSERT data (hotels, rooms, guests, bookings + advance payments)
-- =====================================================================
INSERT INTO room_types(type_name, multiplier, image) VALUES
('Standard',1.0,'standard.jpg'),('Deluxe',1.5,'deluxe.jpg'),('Suite',2.5,'suite.jpg');

INSERT INTO hotels(name,destination,place,address,lat,lng,base_rate,pickup_fee,drop_fee) VALUES
('Hooghly Heritage Inn','Kolkata','Kolkata, West Bengal','Park Street area, Kolkata',22.5726,88.3639,3500,600,600),
('Capital Crown Hotel','Delhi','New Delhi','Connaught Place, New Delhi',28.6139,77.2090,5000,800,800),
('Umiam Hills Retreat','Meghalaya','Shillong','Shillong, Meghalaya',25.5788,91.8933,3000,1500,1500),
('Kanchenjunga View Resort','Sikkim','Gangtok','MG Marg, Gangtok, Sikkim',27.3389,88.6065,3200,1200,1200),
('Tea Garden Lodge','Darjeeling','Darjeeling','Mall Road, Darjeeling',27.0360,88.2627,2800,1800,1800),
('Palm Shore Resort','Goa','Panaji','Panaji, Goa',15.4909,73.8278,4500,900,900),
('Marine Drive Grand','Mumbai','Mumbai','Colaba, Mumbai',18.9220,72.8347,6000,1000,1000),
('Dal Lake Houseboat Hotel','Jammu and Kashmir','Srinagar','Dal Lake, Srinagar',34.0837,74.7973,4000,900,900),
('Ridge View Manor','Shimla','Shimla','The Ridge, Shimla',31.1048,77.1734,3600,1500,1500),
('Lakeside Palace Hotel','Madhya Pradesh','Bhopal','Upper Lake, Bhopal',23.2599,77.4126,2500,500,500);

-- 2 rooms of every type in every hotel, e.g. hotel 1 / type 1 -> 111, 112
INSERT INTO rooms(hotel_id,type_id,room_no)
SELECT h.hotel_id, t.type_id, CAST(h.hotel_id*100 + t.type_id*10 + n.n AS CHAR)
FROM hotels h, room_types t, (SELECT 1 AS n UNION SELECT 2) n;

INSERT INTO sightseeing(hotel_id,place,price_per_person) VALUES
(1,'Victoria Memorial & Howrah Bridge',600),(1,'Dakshineswar & Belur Math',500),
(2,'Red Fort & India Gate',900),(2,'Qutub Minar & Humayun''s Tomb',800),
(3,'Living Root Bridges, Cherrapunji',1500),(3,'Dawki & Mawlynnong',1800),
(4,'Tsomgo Lake & Baba Mandir',1700),(4,'Rumtek Monastery',700),
(5,'Tiger Hill Sunrise',600),(5,'Toy Train Joy Ride',1500),
(6,'North Goa Beaches',1000),(6,'Old Goa Churches',800),
(7,'Gateway of India & Marine Drive',700),(7,'Elephanta Caves',1100),
(8,'Dal Lake Shikara Ride',800),(8,'Gulmarg Gondola',2000),
(9,'Kufri & Mall Road',900),(9,'Jakhoo Temple',400),
(10,'Sanchi Stupa',1200),(10,'Bhimbetka Rock Shelters',1000);

INSERT INTO guests(full_name,phone,email,city,id_proof) VALUES
('Amit Sharma','9830011111','amit@example.com','Kolkata','Aadhaar-1111'),
('Priya Das','9830022222','priya@example.com','Kolkata','Aadhaar-2222'),
('Rahul Verma','9810033333','rahul@example.com','Delhi','Passport-3333'),
('Sneha Iyer','9820044444','sneha@example.com','Mumbai','Aadhaar-4444'),
('John Dsouza','9890055555','john@example.com','Goa','DL-5555'),
('Fatima Khan','9810066666','fatima@example.com','Delhi','Aadhaar-6666'),
('Tenzin Bhutia','9830077777','tenzin@example.com','Gangtok','Aadhaar-7777'),
('Ananya Roy','9830088888','ananya@example.com','Kolkata','Aadhaar-8888');

-- Look up the room ids first. MySQL does not allow the INSERT itself to read
-- the 'rooms' table because the booking trigger updates 'rooms' (error 1442).
SET @r111  = (SELECT room_id FROM rooms WHERE room_no = '111');
SET @r421  = (SELECT room_id FROM rooms WHERE room_no = '421');
SET @r612  = (SELECT room_id FROM rooms WHERE room_no = '612');
SET @r732  = (SELECT room_id FROM rooms WHERE room_no = '732');
SET @r221  = (SELECT room_id FROM rooms WHERE room_no = '221');
SET @r811  = (SELECT room_id FROM rooms WHERE room_no = '811');
SET @r1021 = (SELECT room_id FROM rooms WHERE room_no = '1021');
SET @r311  = (SELECT room_id FROM rooms WHERE room_no = '311');

-- Bookings (transaction data). Triggers fire on every row.
INSERT INTO bookings(guest_id,room_id,check_in,check_out,total_amount) VALUES
(1,@r111, '2026-11-18','2026-11-23',17500),
(2,@r421, '2026-12-01','2026-12-04',14400),
(3,@r612, '2026-12-24','2026-12-28',18000),
(4,@r732, '2026-10-10','2026-10-12',30000),
(1,@r221, '2026-09-05','2026-09-07',15000),
(5,@r811, '2026-08-10','2026-08-13',12000),
(2,@r1021,'2026-07-04','2026-07-06',7500),
(6,@r311, '2026-12-10','2026-12-13',9000);

INSERT INTO payments(booking_id,amount,method) VALUES
(1,5250,'UPI'),(2,4320,'Card'),(3,5400,'UPI'),(4,9000,'Cash'),
(5,4500,'Card'),(6,3600,'UPI'),(7,2250,'Cash'),(8,2700,'UPI');

-- Stays that already ended are checked out (fires trg_checkout)
UPDATE bookings SET status = 'CheckedOut' WHERE check_out < '2026-11-21';

-- =====================================================================
-- ## 3. SELECT basics: WHERE, DISTINCT, LIKE, BETWEEN, JOIN
-- =====================================================================
SELECT * FROM guests WHERE city = 'Kolkata';
SELECT DISTINCT city FROM guests;
SELECT full_name, phone FROM guests WHERE full_name LIKE 'A%';
SELECT booking_id, check_in, check_out, total_amount
FROM bookings WHERE check_in BETWEEN '2026-12-01' AND '2026-12-31';

-- JOIN across 5 tables
SELECT g.full_name, h.name AS hotel, h.destination, t.type_name, r.room_no, b.check_in, b.check_out
FROM bookings b
JOIN guests g     ON g.guest_id = b.guest_id
JOIN rooms r      ON r.room_id  = b.room_id
JOIN hotels h     ON h.hotel_id = r.hotel_id
JOIN room_types t ON t.type_id  = r.type_id;

-- =====================================================================
-- ## 4. ORDER BY and LIMIT
-- =====================================================================
SELECT booking_id, guest_id, total_amount FROM bookings ORDER BY total_amount DESC LIMIT 3;
SELECT name, destination, base_rate FROM hotels ORDER BY base_rate ASC LIMIT 5;

-- =====================================================================
-- ## 5. GROUP BY, HAVING and reports
-- =====================================================================
-- Occupancy per month
SELECT DATE_FORMAT(check_in, '%Y-%m') AS booking_month,
       COUNT(*) AS bookings,
       SUM(DATEDIFF(check_out, check_in)) AS room_nights
FROM bookings
WHERE status <> 'Cancelled'
GROUP BY booking_month
ORDER BY booking_month;

-- Revenue (advance received) per room type
SELECT t.type_name, SUM(p.amount) AS advance_revenue
FROM payments p
JOIN bookings b   ON b.booking_id = p.booking_id
JOIN rooms r      ON r.room_id    = b.room_id
JOIN room_types t ON t.type_id    = r.type_id
GROUP BY t.type_name;

-- Repeat guests (HAVING)
SELECT g.full_name, COUNT(*) AS stays
FROM bookings b
JOIN guests g ON g.guest_id = b.guest_id
GROUP BY g.guest_id, g.full_name
HAVING COUNT(*) > 1;

-- Hotels earning more than 5000
SELECT h.name, SUM(b.total_amount) AS billed
FROM bookings b
JOIN rooms r  ON r.room_id  = b.room_id
JOIN hotels h ON h.hotel_id = r.hotel_id
GROUP BY h.hotel_id, h.name
HAVING SUM(b.total_amount) > 5000
ORDER BY billed DESC;

-- =====================================================================
-- ## 6. UPDATE
-- =====================================================================
UPDATE guests SET email = 'amit.new@example.com' WHERE guest_id = 1;

-- Goa season price rise of 10%
UPDATE hotels SET base_rate = ROUND(base_rate * 1.10) WHERE destination = 'Goa';

-- Check-out guest Rahul (booking 3) -> trigger frees the room
UPDATE bookings SET status = 'CheckedOut' WHERE booking_id = 3;

-- =====================================================================
-- ## 7. DELETE
-- =====================================================================
-- Guest 1 still has an active booking: trg_guest_guard BLOCKS that delete.
-- It is tested safely in section 9(d) below so the script does not stop.

-- Guest 3 has checked out: delete is allowed
DELETE FROM guests WHERE guest_id = 3;

-- =====================================================================
-- ## 8. VIEWS
-- =====================================================================
CREATE VIEW v_available_rooms AS
SELECT r.room_id, h.name AS hotel, h.destination, t.type_name, r.room_no,
       h.base_rate * t.multiplier AS tariff
FROM rooms r
JOIN hotels h     ON h.hotel_id = r.hotel_id
JOIN room_types t ON t.type_id  = r.type_id
WHERE NOT EXISTS (SELECT 1 FROM bookings b
                  WHERE b.room_id = r.room_id
                    AND b.status = 'Booked'
                    AND CURDATE() >= b.check_in
                    AND CURDATE() <  b.check_out);

CREATE VIEW v_booking_list AS
SELECT b.booking_id, g.full_name AS guest, h.name AS hotel, h.destination,
       t.type_name AS room_type, r.room_no, b.check_in, b.check_out, b.total_amount,
       COALESCE((SELECT SUM(amount) FROM payments p WHERE p.booking_id = b.booking_id), 0) AS advance_paid,
       b.status
FROM bookings b
JOIN guests g     ON g.guest_id = b.guest_id
JOIN rooms r      ON r.room_id  = b.room_id
JOIN hotels h     ON h.hotel_id = r.hotel_id
JOIN room_types t ON t.type_id  = r.type_id;

SELECT * FROM v_available_rooms LIMIT 5;
SELECT * FROM v_booking_list;

-- =====================================================================
-- ## 9. TRANSACTIONS: COMMIT, ROLLBACK, SAVEPOINT
-- =====================================================================
-- (a) COMMIT: booking + 30% advance payment succeed together
SET @r511 = (SELECT room_id FROM rooms WHERE room_no = '511');
START TRANSACTION;
INSERT INTO bookings(guest_id,room_id,check_in,check_out,total_amount)
VALUES (7,@r511,'2027-01-05','2027-01-08',8400);
INSERT INTO payments(booking_id,amount,method)
VALUES ((SELECT MAX(booking_id) FROM bookings),2520,'UPI');
COMMIT;

-- (b) ROLLBACK: undo a risky delete
START TRANSACTION;
DELETE FROM payments;
SELECT COUNT(*) AS payments_inside_txn FROM payments;
ROLLBACK;
SELECT COUNT(*) AS payments_after_rollback FROM payments;

-- (c) SAVEPOINT: roll back only part of a transaction
START TRANSACTION;
INSERT INTO guests(full_name,phone) VALUES ('Temp Guest','0000000001');
SAVEPOINT sp1;
INSERT INTO guests(full_name,phone) VALUES ('Mistake Guest','0000000002');
ROLLBACK TO SAVEPOINT sp1;
COMMIT;
SELECT guest_id, full_name FROM guests ORDER BY guest_id DESC LIMIT 3;

-- (d) Trigger tests: both statements below MUST FAIL.
-- They run inside a procedure with an error handler, so the script keeps going
-- and the result grid shows the error message the trigger raised.
SET @r111b = (SELECT room_id FROM rooms WHERE room_no = '111');

DELIMITER $$
CREATE PROCEDURE sp_run_negative_tests()
BEGIN
  -- Test 1: delete a guest who still has an active booking
  BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 @err = MESSAGE_TEXT;
      SELECT 'Test 1: delete guest 1' AS test, CONCAT('BLOCKED OK -> ', @err) AS result;
    END;
    DELETE FROM guests WHERE guest_id = 1;
    SELECT 'Test 1: delete guest 1' AS test, 'NOT BLOCKED (unexpected)' AS result;
  END;

  -- Test 2: overlapping booking on room 111
  BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 @err = MESSAGE_TEXT;
      SELECT 'Test 2: overlapping booking' AS test, CONCAT('BLOCKED OK -> ', @err) AS result;
    END;
    INSERT INTO bookings(guest_id,room_id,check_in,check_out,total_amount)
    VALUES (7,@r111b,'2026-11-20','2026-11-22',7000);
    SELECT 'Test 2: overlapping booking' AS test, 'NOT BLOCKED (unexpected)' AS result;
  END;
END$$
DELIMITER ;

CALL sp_run_negative_tests();

-- =====================================================================
-- ## 10. Check what the TRIGGERS recorded
-- =====================================================================
SELECT * FROM audit_log ORDER BY log_id;
SELECT room_no, status FROM rooms WHERE status = 'Booked';

-- =====================================================================
-- ## 11. EXPORT to CSV
-- =====================================================================
-- Easiest in Workbench: run the SELECT below, then click "Export" above the
-- result grid and choose CSV.
SELECT * FROM v_booking_list;
-- Server-side alternative (needs secure_file_priv folder, see SHOW VARIABLES LIKE 'secure_file_priv'):
-- SELECT * FROM v_booking_list
-- INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/bookings.csv'
-- FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n';

-- =====================================================================
-- ## 12. IMPORT from CSV  (guests_cleaned.csv)
-- =====================================================================
CREATE TABLE guest_import (
  full_name VARCHAR(100),
  phone     VARCHAR(20),
  email     VARCHAR(100),
  city      VARCHAR(50),
  id_proof  VARCHAR(50)
);

-- Rows from guests_cleaned.csv loaded into staging (60 valid unique records).
INSERT INTO guest_import(full_name,phone,email,city,id_proof) VALUES
('Amit Sharma','9830011111','amit@example.com','Kolkata','Aadhaar-1111'),
('Priya Das','9830022222','priya@example.com','Kolkata','Aadhaar-2222'),
('Rahul Verma','9810033333','rahul@example.com','Delhi','Passport-3333'),
('Sneha Iyer','9820044444','sneha@example.com','Mumbai','Aadhaar-4444'),
('John Dsouza','9890055555','john@example.com','Goa','DL-5555'),
('Fatima Khan','9810066666','fatima@example.com','Delhi','Aadhaar-6666'),
('Tenzin Bhutia','9830077777','tenzin@example.com','Gangtok','Aadhaar-7777'),
('Ananya Roy','9830088888','ananya@example.com','Kolkata','Aadhaar-8888'),
('Karan Mehta','9870099999','karan@example.com','Shimla','Aadhaar-9999'),
('Lakshmi Nair','9847000000','lakshmi@example.com','Kochi','Passport-0000'),
('Arjun Sen','9700000001','arjun.sen1@example.test','Goa','Passport (TEST)'),
('Meera Kapoor','9700000002','meera.kapoor2@example.test','Bhopal','Driving Licence (TEST)'),
('Dev Patel','9700000003','dev.patel3@example.test','Pune','Aadhaar (TEST)'),
('Riya Mukherjee','9700000004','riya.mukherjee4@example.test','Bengaluru','Passport (TEST)'),
('Sanjay Rao','9700000005','sanjay.rao5@example.test','Lucknow','Driving Licence (TEST)'),
('Pooja Banerjee','9700000006','pooja.banerjee6@example.test','Mumbai','Aadhaar (TEST)'),
('Vikram Singh','9700000007','vikram.singh7@example.test','Shimla','Passport (TEST)'),
('Nisha Sharma','9700000008','nisha.sharma8@example.test','Jaipur','Driving Licence (TEST)'),
('Aarav Das','9700000009','aarav.das9@example.test','Hyderabad','Aadhaar (TEST)'),
('Ishita Bose','9700000010','ishita.bose10@example.test','Shillong','Passport (TEST)'),
('Kabir Malhotra','9700000011','kabir.malhotra11@example.test','Delhi','Driving Licence (TEST)'),
('Tanvi Gupta','9700000012','tanvi.gupta12@example.test','Gangtok','Aadhaar (TEST)'),
('Rohan Chatterjee','9700000013','rohan.chatterjee13@example.test','Kochi','Passport (TEST)'),
('Simran Kaur','9700000014','simran.kaur14@example.test','Chennai','Driving Licence (TEST)'),
('Aditya Nair','9700000015','aditya.nair15@example.test','Darjeeling','Aadhaar (TEST)'),
('Neha Jain','9700000016','neha.jain16@example.test','Kolkata','Passport (TEST)'),
('Sourav Ghosh','9700000017','sourav.ghosh17@example.test','Goa','Driving Licence (TEST)'),
('Maya Fernandes','9700000018','maya.fernandes18@example.test','Bhopal','Aadhaar (TEST)'),
('Aniket Roy','9700000019','aniket.roy19@example.test','Pune','Passport (TEST)'),
('Diya Saha','9700000020','diya.saha20@example.test','Bengaluru','Driving Licence (TEST)'),
('Parth Shah','9700000021','parth.shah21@example.test','Lucknow','Aadhaar (TEST)'),
('Ayesha Ali','9700000022','ayesha.ali22@example.test','Mumbai','Passport (TEST)'),
('Kunal Dutta','9700000023','kunal.dutta23@example.test','Shimla','Driving Licence (TEST)'),
('Shruti Menon','9700000024','shruti.menon24@example.test','Jaipur','Aadhaar (TEST)'),
('Manish Yadav','9700000025','manish.yadav25@example.test','Hyderabad','Passport (TEST)'),
('Tara Das','9700000026','tara.das26@example.test','Shillong','Driving Licence (TEST)'),
('Abhishek Bose','9700000027','abhishek.bose27@example.test','Delhi','Aadhaar (TEST)'),
('Zoya Khan','9700000028','zoya.khan28@example.test','Gangtok','Passport (TEST)'),
('Ritwik Paul','9700000029','ritwik.paul29@example.test','Kochi','Driving Licence (TEST)'),
('Sonal Mishra','9700000030','sonal.mishra30@example.test','Chennai','Aadhaar (TEST)'),
('Siddharth Iyer','9700000031','siddharth.iyer31@example.test','Darjeeling','Passport (TEST)'),
('Payal Roy','9700000032','payal.roy32@example.test','Kolkata','Driving Licence (TEST)'),
('Gaurav Thakur','9700000033','gaurav.thakur33@example.test','Goa','Aadhaar (TEST)'),
('Madhuri Sen','9700000034','madhuri.sen34@example.test','Bhopal','Passport (TEST)'),
('Naveen Kumar','9700000035','naveen.kumar35@example.test','Pune','Driving Licence (TEST)'),
('Aditi Chakraborty','9700000036','aditi.chakraborty36@example.test','Bengaluru','Aadhaar (TEST)'),
('Rahul Das','9700000037','rahul.das37@example.test','Lucknow','Passport (TEST)'),
('Kavya Reddy','9700000038','kavya.reddy38@example.test','Mumbai','Driving Licence (TEST)'),
('Imran Sheikh','9700000039','imran.sheikh39@example.test','Shimla','Aadhaar (TEST)'),
('Sreemoyee Mitra','9700000040','sreemoyee.mitra40@example.test','Jaipur','Passport (TEST)'),
('Pranav Joshi','9700000041','pranav.joshi41@example.test','Hyderabad','Driving Licence (TEST)'),
('Anjali Verma','9700000042','anjali.verma42@example.test','Shillong','Aadhaar (TEST)'),
('Deepak Soni','9700000043','deepak.soni43@example.test','Delhi','Passport (TEST)'),
('Moumita Dey','9700000044','moumita.dey44@example.test','Gangtok','Driving Licence (TEST)'),
('Harsh Vardhan','9700000045','harsh.vardhan45@example.test','Kochi','Aadhaar (TEST)'),
('Ritika Das','9700000046','ritika.das46@example.test','Chennai','Passport (TEST)'),
('Nitin Bhat','9700000047','nitin.bhat47@example.test','Darjeeling','Driving Licence (TEST)'),
('Sana Kapoor','9700000048','sana.kapoor48@example.test','Kolkata','Aadhaar (TEST)'),
('Biswajit Pal','9700000049','biswajit.pal49@example.test','Goa','Passport (TEST)'),
('Esha Roy','9700000050','esha.roy50@example.test','Bhopal','Driving Licence (TEST)');

-- OPTIONAL: load the real file instead of the INSERT above.
-- Needs local_infile enabled on the server (SET GLOBAL local_infile = 1;) and
-- in the Workbench connection (Edit Connection > Advanced > Others:
-- OPT_LOCAL_INFILE=1). Use forward slashes in the path.
-- TRUNCATE TABLE guest_import;
-- LOAD DATA LOCAL INFILE 'C:/Users/YourName/Downloads/guests.csv'
-- INTO TABLE guest_import
-- FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
-- LINES TERMINATED BY '\n'          -- use '\r\n' if the file was saved on Windows
-- IGNORE 1 LINES
-- (full_name,phone,email,city,id_proof);
-- Or: right-click the guest_import table > Table Data Import Wizard.

-- Move only NEW guests (phone not already present) into the real table
INSERT INTO guests(full_name,phone,email,city,id_proof)
SELECT i.full_name, i.phone, i.email, i.city, i.id_proof
FROM guest_import i
WHERE NOT EXISTS (SELECT 1 FROM guests g WHERE g.phone = i.phone);

SELECT COUNT(*) AS guests_after_import FROM guests;
SELECT * FROM guests ORDER BY guest_id;

-- =====================================================================
-- ## 13. Pick-up / drop CARS (car name + seat capacity, used by the web page)
-- =====================================================================
CREATE TABLE cars (
  car_id         INT PRIMARY KEY AUTO_INCREMENT,
  car_name       VARCHAR(60),
  seats          INT,
  fee_multiplier DECIMAL(3,1)
);
INSERT INTO cars(car_name,seats,fee_multiplier) VALUES
('Maruti Swift Dzire (Sedan)',4,1.0),('Toyota Innova Crysta (SUV)',7,1.6),('Tempo Traveller (Van)',12,2.5);

-- Car tariff = the hotel's pick-up / drop fee x the car's multiplier
CREATE VIEW v_car_tariff AS
SELECT h.hotel_id, c.car_id, c.car_name, c.seats,
       ROUND(h.pickup_fee * c.fee_multiplier) AS pickup_tariff,
       ROUND(h.drop_fee   * c.fee_multiplier) AS drop_tariff
FROM hotels h CROSS JOIN cars c;
SELECT * FROM v_car_tariff WHERE hotel_id = 1;

-- Turn safe-update mode back on for this session
SET SQL_SAFE_UPDATES = 1;
