--Create Tables Code--
create table Countries(
CountryID     int             not null      identity(1,1),
CountryCode   char(2)         not null,
CountryName   varchar(50)     not null
primary key (CountryID))

create table Locations(
LocationID    bigint          not null      identity(1,1),
CountryID     int             not null,
LocationName  varchar(50)     not null,
Latitude      int      check (Latitude >= -90 and Latitude <= 90),
Longitude     int      check (Longitude >= -180 and Longitude <= 180),
Altitude      int,
"State"         char(2)
primary key (LocationID)
foreign key (CountryID) references Countries)

create table ICAO(
LocationID    bigint      not null,
ICAO          char(5)     not null
primary key (LocationID, ICAO)
foreign key (LocationID) references Locations)
 
create index Index_LocationName
on Locations(LocationName)

--Problem 4--
--Load Countries--
insert into Countries(CountryCode, CountryName) values ('US', 'United States of America')
insert into Countries(CountryCode, CountryName) values ('NP', 'Nepal')
insert into Countries(CountryCode, CountryName) values ('JP', 'Japan')

--Load Locations--
insert into Locations(CountryID, LocationName, Latitude, Longitude, Altitude, [State]) values (1, 'Saint Louis',
39, -94, 184, 'MO')
insert into Locations(CountryID, LocationName, Latitude, Longitude, Altitude, [State]) values (1, 'Alexandria',
31, -92, 34, 'LA')
insert into Locations(CountryID, LocationName, Latitude, Longitude, Altitude, [State]) values (1, 'Dallas',
32, -96, 148, 'TX')
insert into Locations(CountryID, LocationName, Latitude, Longitude, Altitude, [State]) values (1, 'Chicago',
41, -87, 203, 'IL')
insert into Locations(CountryID, LocationName, Latitude, Longitude, Altitude, [State]) values (1, 'Houston',
29, -95, 14, 'TX')
insert into Locations(CountryID, LocationName, Latitude, Longitude, Altitude, [State]) values (2, 'Kathmandu',
27, 85, 1337, '')
insert into Locations(CountryID, LocationName, Latitude, Longitude, Altitude, [State]) values (2, 'Surkhet',
28, 81, 720, '')
insert into Locations(CountryID, LocationName, Latitude, Longitude, Altitude, [State]) values (2, 'Pokhara',
28, 84, 827, '')
insert into Locations(CountryID, LocationName, Latitude, Longitude, Altitude, [State]) values (3, 'Tokyo',
35, 139, 41, '')

--Load ICAO--
insert into ICAO(LocationID, ICAO) values (1, 'KSTL')
insert into ICAO(LocationID, ICAO) values (2, 'KESF')
insert into ICAO(LocationID, ICAO) values (3, 'KDAL')
insert into ICAO(LocationID, ICAO) values (3, 'KDFW')
insert into ICAO(LocationID, ICAO) values (4, 'KORD')
insert into ICAO(LocationID, ICAO) values (5, 'KHOU')
insert into ICAO(LocationID, ICAO) values (6, 'VNKT')
insert into ICAO(LocationID, ICAO) values (7, 'VNSK')
insert into ICAO(LocationID, ICAO) values (8, 'VNPK')
insert into ICAO(LocationID, ICAO) values (9, 'RJTT')

--Problem 5--
create function GetCountry
(@ICAO char(5))
returns char(2)
as
begin
declare @Return char(2) 
select @Return = C.CountryCode
from Countries C
join Locations L
on C.CountryID = L.CountryID
join ICAO I
on L.LocationID = I.LocationID
where I.ICAO = @ICAO 
return @Return
end

--Test Code--
select dbo.GetCountry('KORD')
select dbo.GetCountry('VNSK')
select dbo.GetCountry('RJTT')

--Problem 6--
create procedure "LocationAltitude"
@ICAO char(5)
as
begin
select C.CountryName, L.LocationName, L.Altitude
from Countries C
join Locations L
on C.CountryID = L.CountryID
join ICAO I
on L.LocationID = I.LocationID
where I.ICAO = @ICAO
end

--Test Code--
exec LocationAltitude 'KORD'
exec LocationAltitude 'VNSK'
exec LocationAltitude 'RJTT'

--Problem 7--
--A--
select top 1 ICAO
from ICAO I
join Locations L
on I.LocationID = L.LocationID
order by L.Altitude desc

--B--
select count(ICAO)
from ICAO I
join Locations L
on I.LocationID = L.LocationID
where [State] = 'MO'

--C--
select top 1 C.CountryName
from Countries C
join Locations L
on C.CountryID = L.CountryID
join ICAO I
on L.LocationID = I.LocationID
group by C.CountryName
order by count(C.CountryName) desc

--D--
select top 1 I.ICAO, C.CountryName
from ICAO I
join Locations L
on I.LocationID = L.LocationID
join Countries C
on L.CountryID = C.CountryID
group by I.ICAO, C.CountryName
order by max(L.Latitude) desc

--Problem 8--
select C.CountryName, count(I.ICAO) as NumberOfICAOs
from Countries C
join Locations L
on C.CountryID = L.CountryID
join ICAO I
on L.LocationID = I.LocationID
group by C.CountryName
order by C.CountryName asc

--Problem 9--
--Create Table--
create table "Log"(
ID       bigint        not null      identity(1,1),
"User"   varchar(25)   not null,
ComputerName    varchar(25)      not null,
"Date"       datetime        not null,
"Action" 	   char(1)        not null
primary key (ID))

--Trigger--
create trigger trg_Log
on Locations
after insert, update, delete
as
begin
declare @Action char(1), @User varchar(50), @ComputerName varchar(50), @Date datetime
set @Action = 'A'
set @User = SUSER_SNAME()
set @ComputerName = Host_Name() 
set @Date = getdate()
if exists(select * from deleted)
begin
set @Action =
case
when exists(select * from inserted) then 'M'
else 'D'                  
end
end
else
if not exists(select * from inserted) return
insert into [Log]([User], ComputerName, [Date], [Action]) values (@User, @ComputerName, @Date, @Action)
end










