--TABLE CREATION CODE--
create table Member(
Member_ID           int             not null      identity(1,1),
Member_FName        varchar(20)     not null,
Member_MInitial     varchar(1),
Member_LName        varchar(20)     not null,
Member_Suffix       varchar(3),
Member_Address      varchar(30)     not null,
Member_City         varchar(15)     not null,
Member_State        varchar(2)      not null,
Member_ZipCode      nvarchar(6)     not null,
Member_Email        varchar(40),
Member_AreaCode     nvarchar(3)     not null,
Member_Phone        nvarchar(7)     not null,
Member_LateCharge   money           default(0),
Member_StartDate    datetime        not null
primary key (Member_ID, Member_FName, Member_LName, Member_Suffix))

create table Distributor(
Distributor_ID                int             not null      identity(1,1),
Distributor_Name              varchar(50)     not null,
Distributor_Address           varchar(80)     not null,
Distributor_City              varchar(30)     not null,
Distributor_State             varchar(2)      not null,
Distributor_ZipCode           nvarchar(6)     not null,
Distributor_AreaCode		  nvarchar(3)     not null,
Distributor_Phone             nvarchar(7)    not null,
Distributor_ContactPerson     varchar(50)     not null
primary key (Distributor_ID))

create table Video(
Video_ID                  int             not null      identity(1,1),
Video_Title               varchar(50)     not null,
Video_Director            varchar(50)     not null,
Video_ReleaseDate         date            not null,
Video_Description         varchar(1200)    not null, 
Video_Cost                money           not null,
Video_Availability        varchar(15)     default('Available'),
Video_RentalDays          int             not null,
Video_DateRented          datetime,
Video_DateDue             datetime,
Distributor_ID            int             not null
primary key (Video_ID)
foreign key (Distributor_ID) references Distributor)

create table "Transaction"(
Transaction_ID      int             not null      identity(1,1),
Member_ID           int             not null,
Video_ID            int             not null,
Transaction_Type    varchar(6)      not null,
Transaction_Date    datetime            not null
primary key (Transaction_ID)
foreign key (Member_ID) references Member)

create table TransactionLineItems(
LineItem_ID         int             not null      identity(1,1),
Video_ID            int             not null,
Transaction_ID      int             not null,
RentalDate          datetime            not null,
RentalCost           money,
Member_LateCharge    money        default(0),
Rental_Total         money        default(0)   
primary key (LineItem_ID, Video_ID),
foreign key (Transaction_ID) references [Transaction],
foreign key (Video_ID) references Video)

create table ReturnVideo(
ReturnVid_ID         int     not null       identity(1,1),
Transaction_ID       int     not null,
Member_ID            int     not null,
Video_ID             int     not null,
Return_Date          datetime    not null,
Return_DaysLate      int     not null,
ChargePerDay         money   default(1.50),
Return_LateCharge    money   
primary key (ReturnVid_ID, Video_ID)
foreign key (Transaction_ID) references [Transaction],
foreign key (Member_ID) references Member,
foreign key (Video_ID) references Video)

create table DamagedVideo(
Video_ID           int,
DamageDescription  varchar(100)
primary key (Video_ID)
foreign key (Video_ID) references Video)

--TRIGGERS--
create trigger T_UpdateVideoCost
on Video
after Update
as
begin
declare @Video_Cost money, @Video_ID int, @Video_DateRented datetime, @Video_RentalDays int, @Video_Availability varchar(15),
@Transaction_ID int 
select @Video_Cost = Video_Cost, @Video_ID = inserted.Video_ID, @Video_DateRented = Video_DateRented, 
@Video_RentalDays = Video_RentalDays, @Video_Availability = Video_Availability, @Transaction_ID = T.Transaction_ID
from inserted
join TransactionLineItems T
on inserted.Video_ID = T.Video_ID
if @Video_Availability = 'Unavailable'
begin
update TransactionLineItems
set RentalCost = @Video_Cost
where Video_ID = @Video_ID and Transaction_ID = @Transaction_ID 
update Video
set Video_DateDue = dbo.CalcDueDate(@Video_ID)
where Video_ID = @Video_ID
end
end

create trigger T_VideoRent
on TransactionLineItems
after insert
as
begin
declare @Video_ID int, @Transaction_ID int, @Member_ID int
select @Video_ID = I.Video_ID, @Transaction_ID = I.Transaction_ID, @Member_ID = T.Member_ID
from inserted I
join [Transaction] T
on I.Transaction_ID = T.Transaction_ID
join Member M
on T.Member_ID = T.Member_ID
update Video
set Video_Availability = 'Unavailable', Video_DateRented = getdate()
where Video_ID = @Video_ID
update TransactionLineItems
set Member_LateCharge = dbo.ReturnLateCharge(@Member_ID) 
where Transaction_ID = @Transaction_ID
update TransactionLineItems
set Rental_Total = dbo.RentalTotal(@Transaction_ID)
where Transaction_ID = @Transaction_ID
end

create trigger T_VideoReturn
on ReturnVideo
after insert
as
begin
declare @Video_ID int, @Member_ID int, @Return_LateCharge money
select @Video_ID = Video_ID, @Member_ID = Member_ID, @Return_LateCharge = Return_LateCharge
from inserted
update Video
set Video_Availability = 'Available'
where Video_ID = @Video_ID
update Member
set Member_LateCharge = Member_LateCharge + @Return_LateCharge
where Member_ID = @Member_ID
end

create trigger T_TransRent
on [Transaction]
after insert
as
begin 
declare @Transaction_Type varchar(6), @Transaction_ID int, @Video_ID int, @Transaction_Date datetime, @Member_ID int,
@Video_DateDue datetime
select @Transaction_Type = Transaction_Type, @Transaction_ID = Transaction_ID, @Video_ID = inserted.Video_ID, 
@Transaction_Date = Transaction_Date, @Member_ID = Member_ID, @Video_DateDue = V.Video_DateDue
from inserted
join Video V
on inserted.Video_ID = V.Video_ID
if @Transaction_Type = 'Rent'
begin
exec SP_RentProcess @Video_ID, @Transaction_ID, @Transaction_Date 
end
else
exec SP_ReturnProcess @Member_ID, @Video_ID, @Transaction_ID, @Transaction_Date, @Video_DateDue
end

create trigger T_DamagedVideo
on DamagedVideo
after insert
as
begin
declare @Video_ID int, @Video_Availability varchar(15) 
select @Video_ID = I.Video_ID, @Video_Availability = V.Video_Availability 
from inserted I
join Video V
on I.Video_ID = V.Video_ID
if @Video_Availability = 'Available'
begin
update Video
set Video_Availability = 'Damaged'
where Video_ID = @Video_ID
end
else
print 'Video is currently unavailable, please choose another.'
end

--FUNCTIONS--
create function RentalTotal
(@Transaction_ID int)
returns money
as
begin
declare @Return money
select @Return = Member_Latecharge + RentalCost 
from TransactionLineItems
where Transaction_ID = @Transaction_ID
return @return
end

create function ReturnLateCharge
(@Member_ID int)
returns money
as
begin
declare @Return money
select @Return = Member_LateCharge 
from Member
where Member_ID = @Member_ID
return @return
end

create function CalcDueDate
(@Video_ID int)
returns datetime
as
begin
declare @Return datetime
select @Return = dateadd(day, Video_RentalDays, Video_DateRented) 
from Video
where Video_ID = @Video_ID
return @return
end

create function CalcDaysLate
(@Video_ID int)
returns int
as
begin
declare @Return int
select @Return = case
when datediff(day, Video_DateDue, getdate()) <= 0 then 0
when datediff(day, Video_DateDue, getdate()) > 0 then datediff(day, Video_DateDue, getdate())
end 
from Video
where Video_ID = @Video_ID
return @Return
end

--MISC COMMANDS--
--DROP TABLE CODE--
drop table DamagedVideo
drop table ReturnVideo
drop table TransactionLineItems
drop table [Transaction]
drop table Video
drop table Distributor
drop table Member

--DISPLAY LOADING INFO--
select * from Distributor
select * from Video
select * from Member
select * from DamagedVideo
select * from ReturnVideo
select * from [Transaction]
select * from TransactionLineItems

--LOAD DIRECTORS--
exec SP_LoadDirectors

--LOAD VIDEOS--
exec SP_LoadVideos

--LOAD MEMBERS--
exec SP_AddMember 'Arthur', 'M', 'Buckowitz', '1736 Coupru Ct.', 'St. Peters', 'MO', '63376', 
'buckowitzjr.arthur@yahoo.com', '314', '5418295'
exec SP_AddMember 'Jenny', 'A', 'Buckowitz', '1736 Coupru Ct.', 'St. Peters', 'MO', '63376', 
'donavon79@hotmail.com', '314', '5418285'
exec SP_AddMember 'John', '', 'Doe', '627 Thatone St.', 'St. Charles', 'MO', '63365', 
'johndoe@yahoo.com', '314', '9876543'
exec SP_AddMember 'Jane', '', 'Doe', '659 Thatone St.', 'Florissant', 'MO', '63033', 
'janedoe@hotmail.com', '314', '1234567'
exec SP_AddMember 'Michael', 'J', 'Dunce', '3975 Moron Way', 'Brainlessville', 'OH', '97265', 
'dummy@yahoo.com', '566', '6824674'
exec SP_AddMember 'Bilbo', '', 'Baggins', '169 Hobbit Lane', 'Shire', 'MS', '85775', 
'bilby@hotmail.com', '398', '2348954'
exec SP_AddMember 'Jim', 'L', 'Yep', '1 St.', 'Overthere', 'IL', '58374', 
'jly@yahoo.com', '566', '8345623'
exec SP_AddMember 'Horace', 'P', 'McGibbles', '742 Tats', 'Schmelly', 'NY', '92634', 
'mcgibs@hotmail.com', '675', '6574654'

--LOAD DAMAGED VIDEOS--
exec SP_DamagedVideo 10, 'Scratched'   
exec SP_DamagedVideo 23, 'Cracked'
exec SP_DamagedVideo 128, 'Scratched'
exec SP_DamagedVideo 355, 'Scratched'
exec SP_DamagedVideo 522, 'Cracked'

--MEMBER RENTING CODE--
exec SP_RentVideo 1, 295
exec SP_RentVideo 2, 7
exec SP_RentVideo 3, 2
exec SP_RentVideo 4, 14
exec SP_RentVideo 5, 16
exec SP_RentVideo 5, 20
exec SP_RentVideo 1, 46
exec SP_RentVideo 2, 55
exec SP_RentVideo 3, 25
exec SP_RentVideo 4, 69
exec SP_RentVideo 5, 83
exec SP_RentVideo 5, 100
exec SP_RentVideo 1, 67
exec SP_RentVideo 2, 74
exec SP_RentVideo 3, 96
exec SP_RentVideo 4, 49
exec SP_RentVideo 5, 50
exec SP_RentVideo 5, 109

--MEMBER RETURN CODE--
exec SP_ReturnVideo 1, 5
exec SP_ReturnVideo 2, 7
exec SP_ReturnVideo 3, 2
exec SP_ReturnVideo 4, 14
exec SP_ReturnVideo 5, 16
exec SP_ReturnVideo 5, 20
exec SP_ReturnVideo 1, 46
exec SP_ReturnVideo 2, 55
exec SP_ReturnVideo 3, 25
exec SP_ReturnVideo 4, 69
exec SP_ReturnVideo 5, 83
exec SP_ReturnVideo 5, 100
exec SP_ReturnVideo 1, 67
exec SP_ReturnVideo 2, 74
exec SP_ReturnVideo 3, 96
exec SP_ReturnVideo 4, 49
exec SP_ReturnVideo 5, 50
exec SP_ReturnVideo 5, 109
*/

--Stored Procedure for inserting Videos--
create procedure "SP_LoadVideos"
as
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cloverfield', 'J. J. Abrams', '2008-01-18', 'The film is presented as found footage from a personal video 
camera recovered by the United States Department of Defense. A disclaimer text states that the footage is of a case 
designated "Cloverfield" and was found in the area "formerly known as Central Park". The video consists chiefly of 
segments taped the night of Friday, May 22, 2009. The newer segments were taped over older video that is shown 
occasionally.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Mission: Impossible III', 'J. J. Abrams', '2006-05-05', 'Ethan Hunt (Tom Cruise) has retired from active field work for the 
Impossible Missions Force (IMF) and instead trains new recruits while settling down with his fiancée Julia Meade (Michelle Monaghan), 
a nurse at a local hospital who is unaware of Ethans past. Ethan is approached by fellow IMF agent John Musgrave (Billy Crudup) 
about a mission for him: rescue one of Ethans protégés, Lindsey Farris (Keri Russell), who was captured while investigating arms 
dealer Owen Davian (Philip Seymour Hoffman). Musgrave has already prepared a team for Ethan, consisting of Declan Gormley 
(Jonathan Rhys Meyers), Zhen Lei (Maggie Q), and his old partner Luther Stickell (Ving Rhames), in Berlin, Germany.', 4.75, 3, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Star Trek', 'J. J. Abrams', '2009-05-08', 'In 2233, the Federation starship USS Kelvin is investigating a "lightning storm" in space. 
A Romulan ship, the Narada, emerges from the storm and attacks the Kelvin. Naradas first officer, Ayel, demands that the Kelvins 
Captain Robau come aboard to discuss a cease fire. Once aboard, Robau is questioned about an "Ambassador Spock", who he states 
that he is "not familiar with", as well as the current stardate, after which the Naradas commander, Nero, flies into a rage and kills 
him, before continuing to attack the Kelvin. The Kelvins first officer, Lieutenant Commander George Kirk, orders the ships personnel 
evacuated via shuttlecraft, including his pregnant wife, Winona. Kirk steers the Kelvin on a collision course at the cost of his own life, 
while Winona gives birth to their son, James Tiberius Kirk.', 4.75, 3, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Halloween', 'John Carpenter', '1978-10-25', 'On Halloween night, 1963, in fictional Haddonfield, Illinois, 6-year-old Michael 
Myers (Will Sandin) murders his older teenage sister Judith (Sandy Johnson), stabbing her repeatedly with a butcher knife, after she 
had sex with her boyfriend. Fifteen years later, on October 30, 1978, Michael escapes the hospital in Smiths Grove, Illinois where he 
had been committed since the murder, stealing the car that was to take him to a court hearing.', 3.25, 5, 2)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Cable Guy', 'Ben Stiller', '1996-06-14', 'After a failed marriage proposal to his girlfriend Robin Harris (Leslie Mann), Steven 
M. Kovacs (Matthew Broderick) moves into his own apartment after they agree to spend some time apart. Enthusiastic cable guy 
Ernie "Chip" Douglas (Jim Carrey), an eccentric man with a lisp, installs his cable. Taking advice from his friend Rick (Jack Black), 
Steven bribes Chip to give him free movie channels, to which Chip agrees. Before he leaves, Chip gets Steven to hang out with him 
the next day and makes him one of his "preferred customers".', 3.25, 5, 3)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Anchorman: The Legend of Ron Burgundy', 'Adam McKay', '2004-07-09', 'In 1975, Ron Burgundy (Will Ferrell) is the famous and 
successful anchorman for San Diegos KVWN-TV Channel 4 Evening News. He works alongside his friends on the news team: 
fashion-oriented lead field reporter Brian Fantana (Paul Rudd), sportscaster Champion "Champ" Kind (David Koechner), and a "legally 
retarded" chief meteorologist Brick Tamland (Steve Carell). The team is notified by their boss, Ed Harken (Fred Willard), that their 
station has maintained its long-held status as the highest-rated news program in San Diego, leading them to throw a wild party. Ron 
sees an attractive blond woman and immediately tries to hit on her. After an awkward, failed pick-up attempt, the woman leaves.', 4.75, 3, 4) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The 40-Year-Old Virgin', 'Judd Apatow', '2005-08-19', 'Andy Stitzer (Steve Carell) is the eponymous 40-year-old virgin; he is 
involuntarily celibate. He lives alone, and is somewhat childlike; he collects action figures, plays video games, and his social life 
seems to consist of watching Survivor with his elderly neighbors. He works in the stockroom at an electronics store called SmartTech. 
When a friend drops out of a poker game, Andys co-workers David (Paul Rudd), Cal (Seth Rogen), and Jay (Romany Malco) reluctantly 
invite Andy to join them. At the game, when conversation turns to past sexual exploits, Andy desperately makes up a story, but when 
he compares the feel of a womans breast to a "bag of sand", he is forced to admit his virginity. Feeling sorry for him (but also 
generally mocking him), the group resolves to help Andy lose his virginity.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Knocked Up', 'Judd Apatow', '2007-06-01', 'Ben Stone (Seth Rogen) is laid-back and sardonic. He lives off funds received in 
compensation for an injury and sporadically works on a celebrity porn website with his roommates, in between smoking marijuana 
or going off with them at theme parks such as Knotts Berry Farm. Alison Scott (Katherine Heigl) is a career-minded woman who has 
just been given an on-air role with E! and is living in the pool house with her sister Debbies (Leslie Mann) family. While celebrating 
her promotion, Alison meets Ben at a local nightclub. After a night of drinking, they end up having sex. Due to a misunderstanding, 
they do not use protection: Alison uses the phrase "Just do it already" to encourage Ben to put the condom on, but he misinterprets 
this to mean to dispense with using one. The following morning, they quickly learn over breakfast that they have little in common 
and go their separate ways, which leaves Ben visibly upset.', 4.75, 3, 5) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Superbad', 'Greg Mottola', '2007-08-17', 'Seth (Jonah Hill) and Evan (Michael Cera) are two high school seniors who lament their 
virginity and poor social standing. Best friends since childhood, the two are about to go off to different colleges, as Seth did not get 
accepted into Dartmouth. After Seth is paired with Jules (Emma Stone) during Home-Ec class, she invites him to a party at her house 
later that night. Later, Fogell (Christopher Mintz-Plasse) comes up to the two and reveals his plans to obtain a fake ID during lunch. 
Seth uses this to his advantage and promises to bring alcohol to Jules party.', 4.75, 3, 3) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Donnie Darko', 'Richard Kelly', '2001-10-26', 'On October 2, 1988, Donnie Darko (Jake Gyllenhaal), a troubled teenager living in 
Middlesex, Virginia, is awakened and led outside by a figure in a monstrous rabbit costume, who introduces himself as "Frank" and 
tells him the world will end in 28 days, 6 hours, 42 minutes and 12 seconds. At dawn, Donnie awakens on a golf course and returns 
home to find a jet engine has crashed into his bedroom. His older sister, Elizabeth (Maggie Gyllenhaal), informs him the FAA 
investigators dont know where it came from.', 4.75, 3, 8)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Never Been Kissed', 'Raja Gosnell', '1999-04-09', 'Josie Geller (Drew Barrymore) is a copy editor for the Chicago Sun-Times who 
has never had a real relationship. One day during a staff meeting, the tyrannical editor-in-chief, Rigfort (Garry Marshall) assigns her 
to report undercover at a high school to help parents become more aware of their childrens lives.  Josie tells her brother Rob (David 
Arquette) about the assignment, and he reminds her that during high school she was a misfit labelled "Josie Grossie", a nickname 
which continues to haunt her.', 3.25, 5, 6)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Duplex', 'Danny DeVito', '2003-09-26', 'Alex Rose and Nancy Kendricks are a young, professional, New York couple in search of 
their dream home. When they finally find the perfect Brooklyn brownstone they are giddy with anticipation. The duplex is a dream 
come true, complete with multiple fireplaces, except for one thing: Mrs. Connelly, the old lady who lives on the rent-controlled top 
floor. Assuming she is elderly and ill, they take the apartment.', 4.75, 3, 9)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Music and Lyrics', 'Marc Lawrence', '2007-02-14', 'At the beginning of the film, Alex is a washed-up former pop star who is 
attempting to revive his career by hitching his career to the rising star of Cora Corman, a young megastar who has asked him to write 
a song titled "Way Back Into Love." During an unsuccessful attempt to come up with words for the song, he discovers that the woman 
who waters his plants, Sophie Fisher (Drew Barrymore), has a gift for writing lyrics. Sophie, a former creative writing student reeling 
from a disastrous romance with her former English professor Sloan Cates (Campbell Scott), initially refuses. Alex cajoles her into 
helping him by using a few quickly-chosen phrases she has given him as the basis for a song. Over the next few days, they grow closer 
while writing the words and music together, much to the delight of Sophies older sister Rhonda (Kristen Johnston), a huge fan of 
Alexs.', 4.75, 3, 10) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Charlies Angels', 'Joseph McGinty Nichol', '2000-11-03', 'Natalie Cook (Cameron Diaz), Dylan Sanders (Drew Barrymore) and 
Alex Munday (Lucy Liu) are the "Angels," three talented, tough, attractive women who work as private investigators for an unseen 
millionaire named Charlie (voiced by Forsythe). Charlie uses a speaker in his offices to communicate with the Angels, and his assistant 
Bosley (Bill Murray) works with them directly when needed.', 4.75, 3, 3)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Pulp Fiction', 'Quentin Tarantino', '1994-10-14', 'As Jules and Vincent eat breakfast in a coffee shop the discussion returns to 
Juless decision to retire. In a brief cutaway, we see "Pumpkin" and "Honey Bunny" shortly before they initiate the hold-up from the 
movies first scene. While Vincent is in the bathroom, the hold-up commences. "Pumpkin" demands all of the patrons valuables, 
including Juless mysterious case. Jules surprises "Pumpkin" (whom he calls "Ringo"), holding him at gunpoint. "Honey Bunny" (whose 
name turns out to be Yolanda), hysterical, trains her gun on Jules. Vincent emerges from the restroom with his gun trained on her, 
creating a Mexican standoff. Reprising his pseudo-biblical passage, Jules expresses his ambivalence about his life of crime.', 3.25, 5, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Kill Bill: Volume 1', 'Quentin Tarantino', '2003-10-03', '"The Bride", a former member of an assassination team who seeks 
revenge on her ex-colleagues who massacred members of her wedding party and tried to kill her. During the first movie she succeeds 
in killing two of the five members.', 4.75, 3, 9) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Kill Bill: Volume 2', 'Quentin Tarantino', '2004-04-16', '"The Bride", a former member of an assassination team who seeks 
revenge on her ex-colleagues who massacred members of her wedding party and tried to kill her. The film is often noted for its stylish 
direction and its homages to film genres such as Hong Kong martial arts films, Japanese chanbara films, Italian spaghetti westerns, 
girls with guns, and rape and revenge.', 4.75, 3, 9)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('An Inconvenient Truth', 'Davis Guggenheim', '2006-05-24', 'An Inconvenient Truth focuses on Al Gore and on his travels in 
support of his efforts to educate the public about the severity of the climate crisis. Gore says, "Ive been trying to tell this story for a 
long time and I feel as if Ive failed to get the message across."[6] The film documents a Keynote presentation (which Gore refers to 
as "the slide show") that Gore has presented throughout the world. It intersperses Gores exploration of data and predictions regarding 
climate change and its potential for disaster with his own life story.', 4.75, 3, 11)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Reservoir Dogs', 'Quentin Tarantino', '1992-10-23', 'Eight men eat breakfast at a Los Angeles diner before their planned diamond 
heist. Six of them use aliases: Mr. Blonde (Michael Madsen), Mr. Blue (Eddie Bunker), Mr. Brown (Quentin Tarantino), Mr. Orange (Tim 
Roth), Mr. Pink (Steve Buscemi), and Mr. White (Harvey Keitel). With them are gangster Joe Cabot (Lawrence Tierney), the organizer 
of the heist and his son, "Nice Guy" Eddie (Chris Penn).', 3.25, 5, 9)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Good Will Hunting', 'Gus Van Sant', '1997-12-05', '20-year-old Will Hunting (Matt Damon) of South Boston has a genius-level 
intellect but chooses to work as a janitor at the Massachusetts Institute of Technology and spend his free time with his friends Chuckie 
Sullivan (Ben Affleck), Billy McBride (Cole Hauser) and Morgan OMally (Casey Affleck). When Fields Medal-winning combinatorialist 
Professor Gerald Lambeau (Stellan Skarsgård) posts a difficult problem taken from algebraic graph theory as a challenge for his 
graduate students to solve, Will solves the problem quickly but anonymously. Lambeau posts a much more difficult problem and 
chances upon Will solving it, but Will flees. Will meets Skylar (Minnie Driver), a British student about to graduate from Harvard 
University and pursue a graduate degree at Stanford University School of Medicine in California.', 3.25, 5, 9) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Air Force One', 'Wolfgang Petersen', '1997-07-25', 'A joint military operation between Russian and American special operations 
forces ends with the capture of General Ivan Radek (Jürgen Prochnow), the dictator of a rogue terrorist regime in Kazakhstan that 
had taken possession of an arsenal of former Soviet nuclear weapons, who is now taken to a Russian maximum security prison. Three 
weeks later, a diplomatic dinner is held in Moscow to celebrate the capture of the Kazakh dictator, at which President of the United 
States James Marshall (Harrison Ford) expresses his remorse that action had not been taken sooner to prevent the suffering that 
Radek caused. He also vows that his administration will take a firmer stance against despotism and refuse to negotiate with terrorists.', 
3.25, 5, 3) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Hurricane', 'Norman Jewison', '1999-12-29', 'The film tells the story of middleweight boxer Rubin "Hurricane" Carter, whose 
conviction for a Paterson, New Jersey triple murder was set aside after he had spent almost 20 years in prison. Narrating Carters life, 
the film concentrates on the period between 1966 and 1985. It describes his fight against the conviction for triple murder and how he 
copes with nearly twenty years in prison. In a parallel plot, an underprivileged youth from Brooklyn, Lesra Martin, becomes interested 
in Carters life and destiny after reading Carters autobiography, and convinces his Canadian foster family to commit themselves to his 
case. The story culminates with Carters legal teams successful pleas to Judge H. Lee Sarokin of the United States District Court for 
the District of New Jersey.', 3.25, 5, 5)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Children of Men', 'Alfonso Cuarón', '2006-09-22', 'In 2027, after 18 years of worldwide female infertility, civilization is on the 
brink of collapse as humanity faces the grim reality of extinction. The United Kingdom, one of the few stable nations with a 
functioning government, has been deluged by asylum seekers from around the world, fleeing the chaos and war which has taken hold 
in most countries. In response, Britain has become a militarized police state as British forces round up and detain immigrants. 
Kidnapped by an immigrants rights group known as the Fishes, former activist turned cynical bureaucrat Theo Faron (Clive Owen) is 
brought to its leader, his estranged American wife Julian Taylor (Julianne Moore), from whom he separated after their son died from 
a flu pandemic in 2008.', 4.75, 3, 5)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bring It On', 'Peyton Reed', '2000-08-25', 'Torrance Shipman (Kirsten Dunst) anxiously dreams about her first day of senior year. 
Her boyfriend, Aaron (Richard Hillman), has left for college, and her cheerleading squad, the Toros, is aiming for a sixth consecutive 
national title. Team captain, "Big Red" (Lindsay Sloane), is graduating and Torrance is elected to take her place. Shortly after her 
election, however, a team member is injured and can no longer compete. Torrance replaces her with Missy Pantone (Eliza Dushku), 
a gymnast who recently transferred to the school with her brother, Cliff (Jesse Bradford). Torrance and Cliff develop a flirtatious 
friendship.', 4.75, 3, 5)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Elephant Man', 'David Lynch', '1980-10-03', 'London Hospital surgeon Frederick Treves discovers John Merrick in a Victorian 
freak show in Londons East End, where he is managed by the brutish Bytes. Merrick is deformed to the point that he must wear a hood 
and cap when in public, and Bytes claims he is an imbecile. Treves is professionally intrigued by Merricks condition and pays Bytes to 
bring him to the Hospital so that he can examine him. There, Treves presents Merrick to his colleagues in a lecture theatre, displaying 
him as a physiological curiosity. Treves draws attention to Merricks most life-threatening deformity, his abnormally large skull, which 
compels him to sleep with his head resting upon his knees, as the weight of his skull would asphyxiate him if he were to ever lie down. 
On Merricks return, Bytes beats him severely enough that a sympathetic apprentice alerts Treves, who returns him to the hospital. 
Bytes accuses Treves of likewise exploiting Merrick for his own ends, leading the surgeon to resolve to do what he can to help the 
unfortunate man.', 3.25, 5, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Fly', 'David Cronenberg', '1986-08-15', 'Seth Brundle (Jeff Goldblum), a brilliant but eccentric scientist, meets Veronica 
Quaife (Geena Davis), a journalist for Particle magazine, at a meet-the-press event held by Bartok Science Industries, the company 
that provides funding for Brundles work. Seth takes Veronica back to the warehouse that serves as both his home and laboratory, and 
shows her a project that will change the world: a set of "Telepods" that allows instantaneous teleportation of an object from one pod 
to another. Veronica eventually agrees to document Seths work. Although the Telepods can transport inanimate objects, they do not 
work properly on living things, as is demonstrated when a live baboon is turned inside-out during an experiment. Seth and Veronica 
begin a romantic relationship. Their first sexual encounter provides inspiration for Seth, who successfully reprograms the Telepod 
computer to cope with living creatures, and teleports a second baboon with no apparent harm.', 3.25, 5, 6) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Frances', 'Graeme Clifford', '1982-12-03', 'Born in Seattle, Washington, Frances Elena Farmer is a rebel from a young age, 
winning a high school award by writing an essay called "God Dies" in 1931. Later that decade, she becomes controversial again when 
she wins (and accepts) an all-expenses-paid trip to the USSR in 1935. Determined to become an actress, Frances is equally determined 
not to play the Hollywood game: she refuses to acquiesce to publicity stunts, and insists upon appearing on screen without makeup. 
Her defiance attracts the attention of Broadway playwright Clifford Odets, who convinces Frances that her future rests with the 
Group Theatre.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Young Frankenstein', 'Mel Brooks', '1974-12-15', 'Dr. Frederick Frankenstein (Gene Wilder) is a physician lecturer at an American 
medical school and engaged to the tightly wound Elizabeth (Madeline Kahn). He becomes exasperated when anyone brings up the 
subject of his grandfather, the infamous mad scientist. To disassociate himself from his legacy, Frederick insists that his surname be 
pronounced "Fronk-en-steen".', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Top Gun', 'Tony Scott', '1986-05-16', 'United States Naval Aviator Lieutenant Pete "Maverick" Mitchell (Tom Cruise) flies the 
F-14A Tomcat off USS Enterprise (CVN-65), with Radar Intercept Officer ("RIO") Lieutenant (Junior Grade) Nick "Goose" Bradshaw 
(Anthony Edwards). At the start of the film, wingman "Cougar" (John Stockwell) and his radar intercept officer "Merlin" (Tim Robbins), 
intercept MiG-28s over the Indian Ocean. During the engagement, one of the MiGs manages to get missile lock on Cougar. While 
Maverick realizes that the MiG "(would) have fired by now", if he really meant to fight, and drives off the MiGs, Cougar is too shaken 
afterward to land, despite being low on fuel. Maverick defies orders and shepherds Cougar back to the carrier, despite also being low 
on fuel. After they land, Cougar retires ("turns in his wings"), stating that he has been holding on "too tight" and has lost "the edge", 
almost orphaning his newborn child, whom he has never seen.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Crimson Tide', 'Tony Scott', '1995-05-12', 'In post-Soviet Russia, military units loyal to Vladimir Radchenko, an ultranationalist, 
have taken control of a nuclear missile installation and are threatening nuclear war if either the American or Russian governments 
attempt to confront him.', 3.25, 5, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Rock', 'Michael Bay', '1996-06-07', 'A group of rogue U.S. Force Recon Marines led by disenchanted Brigadier General Frank 
Hummel (Ed Harris) seize a stockpile of deadly VX gas–armed rockets from a heavily guarded US Navy bunker, reluctantly leaving one 
of their men to die in the process, when a bead of the gas falls and breaks. The next day, Hummel and his men, along with more 
renegade Marines Captains Frye (Gregory Sporleder) and Darrow (Tony Todd) (who have never previously served under Hummel) seize 
control of Alcatraz during a guided tour and take 81 tourists hostage in the prison cells. Hummel threatens to launch the stolen 
rockets against the population of San Francisco if the media is alerted or payment is refused or unless the government pays $100 
million in ransom and reparations to the families of Recon Marines, (using money the U.S. earned via illegal weapons sales) who died 
on illegal, clandestine missions under his command and whose deaths were not honored.', 3.25, 5, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Con Air', 'Simon West', '1997-06-06', 'Former U.S. Army Ranger Cameron Poe is sentenced to a maximum-security federal 
penitentiary for using excessive force and killing a drunk man who had been attempting to assault his pregnant wife, Tricia. Eight 
years later, Poe is paroled on good behavior, and eager to see his daughter Casey whom he has never met. Poe is arranged to be flown 
back home to Alabama on the C-123 Jailbird where he will be released on landing; several other prisoners, including his diabetic 
cellmate and friend Mike "Baby-O" ODell and criminal mastermind Cyrus "The Virus" Grissom, as well as Grissoms right-hand man, 
Nathan Jones, are also being transported to a new Supermax prison. DEA agent Duncan Malloy wishes to bring aboard one of his agents, 
Willie Sims, as a prisoner to coax more information out of drug lord Francisco Cindino before he is incarcerated. Vince Larkin, the U.S. 
Marshal overseeing the transfer, agrees to it, but is unaware that Malloy has armed Sims with a gun.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('National Treasure', 'Jon Turteltaub', '2004-11-19', 'Benjamin Franklin Gates (Nicolas Cage) is a historian and amateur cryptologist, 
and the youngest descendant of a long line of treasure hunters. Though Bens father, Patrick Henry Gates, tries to discourage Ben from 
following in the family line, as he had spent over 20 years looking for the national treasure, attracting ridicule on the family name, 
young Ben is encouraged onward by a clue, "The secret lies with Charlotte", from his grandfather John Adams Gates in 1974, that 
could lead to the fabled national treasure hidden by the Founding Fathers of the United States and Freemasons during the American 
Revolutionary War that was entrusted to his family by Charles Carroll of Carrollton in 1832 before his death to find, and protect the 
family name.', 4.75, 3, 15)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Hope Floats', 'Forest Whitaker', '1998-05-29', 'Birdee Pruitt (Sandra Bullock) is a Chicago housewife who is invited onto a talk 
show under the pretense of getting a free makeover. The makeover she is given is hardly what she has in mind...as she is ambushed 
with the revelation that her husband Bill has been having an affair behind her back with her best friend Connie. Humiliated on 
national television, Birdee and her daughter Bernice (Mae Whitman) move back to Birdees hometown of Smithville, Texas with 
Birdees eccentric mother Ramona (Gena Rowlands) to try to make a fresh start. As Birdee and Bernice leave Chicago, Birdee gives 
Bernice a letter from her father, telling Bernice how much he misses her.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Gun Shy', 'Eric Blakeney', '2000-02-04', 'Charlie Mayeaux (Liam Neeson) is an undercover DEA agent suffering from anxiety and 
gastrointestinal problems after a bust gone wrong. During the aforementioned incident, his partner was killed and he found himself 
served up on a platter of watermelon with a gun shoved in his face just before back-up arrived. Charlie, once known for his ease and 
almost "magical" talent on the job, is finding it very hard to return to work. His requests to be taken off the case or retired are denied 
by his bosses, Lonny Ward (Louis Giambalvo) and Dexter Helvenshaw (Mitch Pileggi) as so much time was put into his cover. Charlie 
works with the dream of one day retiring to Ocean Views, a luxury housing complex with servants and utilities.', 4.75, 3, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Miss Congeniality', 'Donald Petrie', '2000-12-22', 'The film opens at a school where a boy is picking on another boy. We see 
Gracie Hart (Mary Ashleigh Green) as a child who beats up the bully and tries to help the victim (whom she liked), who instead 
criticizes her by saying he disliked her because he did not want a girl to help him. She promptly punches the boy in the nose and sulks 
in the playground.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Murder by Numbers', 'Barbet Schroeder', '2002-04-19', 'Richard Haywood, a wealthy and popular high-schooler, secretly teams 
up with another rich kid in his class, brilliant nerd Justin "Bonaparte" Pendleton. His erudition, especially in forensic matters, allows 
them to plan elaborately perfect murders as a perverse form of entertainment. Meeting in a deserted resort, they drink absinthe, 
smoke, and joke around, but pretend to have an adversarial relationship while at school. Justin, in particular, behaves strangely, 
writing a paper about how crime is freedom and vice versa, and creating a composite photograph of himself and Richard.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Two Weeks Notice', 'Marc Lawrence', '2002-12-18', 'Lucy Kelson (Sandra Bullock) is a liberal lawyer who specializes in 
environmental law in New York City. George Wade (Hugh Grant) is an immature billionaire real estate tycoon who has almost 
everything and knows almost nothing. Lucys hard work and devotion to others contrast sharply with Georges world weary 
recklessness and greed.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Miss Congeniality 2: Armed and Fabulous', 'John Pasquin', '2005-03-24', 'Three weeks after the events of the first film, FBI agent 
Gracie Hart (Sandra Bullock) has become a celebrity after she infiltrated a beauty pageant on her last assignment. Her fame results in 
her cover being blown while she is trying to prevent a bank heist.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('All About Steve', 'Phil Traill', '2009-09-04', 'Mary Horowitz, a crossword puzzle writer for the Sacramento Herald, is socially 
awkward and considers her pet hamster her only true friend.  Her parents decide to set her up on a blind date. Marys expectations 
are low, as she tells her hamster. However, she is extremely surprised when her date turns out to be handsome and charming Steve 
Miller, a cameraman for the television news network CCN. However, her feelings for Steve are not reciprocated. After an attempt at 
an intimate moment fails, in part because of her awkwardness and inability to stop talking about vocabulary, Steve fakes a phone call 
about covering the news out of town. Trying to get Mary out of his truck, he tells her he wishes she could be there.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Nightmare Before Christmas', 'Henry Selick', '1993-10-29', 'Halloween Town is a dream world filled with citizens such as 
deformed monsters, ghosts, ghouls, goblins, vampires, werewolves and witches. Jack Skellington ("The Pumpkin King") leads them in a 
frightful celebration every Halloween, but he has grown tired of the same routine year after year. Wandering in the forest outside the 
town center, he accidentally opens a portal to "Christmas Town". Impressed by the feeling and style of Christmas, Jack presents his 
findings and his (somewhat limited) understanding of the festivities to the Halloween Town residents. They fail to grasp his meaning 
and compare everything he says to their idea of Halloween. He reluctantly decides to play along and announces that they will take 
over Christmas.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cabin Boy', 'Adam Resnick', '1994-01-07', 'Nathaniel Mayweather (Chris Elliott) is a snobbish, self-centered, virginal man. He is 
invited by his father to sail to Hawaii aboard the Queen Catherine. After annoying the driver, he is forced to walk the rest of the way.  
Nathaniel makes a wrong turn into a small fishing village where he meets the imbecilic cabin boy/first mate Kenny (Andy Richter). He 
thinks the ship, The Filthy Whore, is a theme boat. It is not until the next morning that Captain Greybar (Ritch Brinkley) finds 
Nathaniel in his room and explains that the boat will not return to dry land for three months.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('James and the Giant Peach', 'Henry Selick', '1996-04-12', 'In the 1930s, James Henry Trotter is a young boy who lives with his 
parents by the sea in the United Kingdom. On Jamess birthday, they plan to go to New York City and visit the Empire State Building, 
the tallest building in the world. However, his parents are later killed by a ghostly rhinoceros from the sky and finds himself living 
with his two cruel aunts, Spiker and Sponge.', 3.25, 5, 15)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('9', 'Shane Acker', '2009-09-09', 'Prior to the events of film, a scientist is ordered by his dictator to create a machine in the 
apparent name of progress. The Scientist uses his own intellect to create the B.R.A.I.N., a thinking robot. However, the dictator 
quickly seizes it and integrates it into the Fabrication Machine, an armature that can construct an army of war machines to destroy 
the dictators enemies. Lacking a soul, the Fabrication Machine is corrupted and exterminates all organic life using toxic gas. In 
desperation, the Scientist uses alchemy to create nine homunculus-like rag dolls known as Stitchpunks using portions of his own soul 
via a talisman, but dies as a result.', 4.75, 3, 16)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bruce Almighty', 'Tom Shadyac', '2003-05-23', 'Bruce Nolan (Jim Carrey) is a television field reporter for Eyewitness News on 
WKBW-TV in Buffalo, New York but desires to be the news anchorman. When he is passed over for the promotion in favour of his 
co-worker rival, Evan Baxter (Steve Carell), he becomes furious and rages during an interview at Niagara Falls, his resulting actions 
leading to his suspension from the station, followed by a series of misfortunes such as getting assaulted by a gang of thugs for standing 
up for a blind man they are beating up as he later on meets with them again and asks them to apologize for beating him up. Bruce 
complains to God that Hes "the one that should be fired".', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Fun with Dick and Jane', 'Dean Parisot', '2005-12-21', 'In January 2000, Dick Harper (Jim Carrey) has been promoted to VP of 
Communication for his company, Globodyne. Soon after, he is asked to appear on the show Money Life, where host Sam Samuels and 
then independent presidential candidate Ralph Nader dub him and all the companys employees as "perverters of the American dream" 
and claim that Globodyne helps the super rich get even wealthier. As they speak, the companys stock goes into a free-fall and is soon 
worthless, along with all the employees pensions, which are in Globodynes stock. Dick arrives home to find his excited wife Jane (Téa 
Leoni), who informs him that she took his advice and quit her job in order to spend more time with their son Billy.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Blood Simple', 'Joel Coen', '1985-01-18', 'Julian Marty (Dan Hedaya), the owner of a Texas bar, suspects his wife Abby (Frances 
McDormand) is having an affair with one of his bartenders, Ray (John Getz). Marty hires private detective Loren Visser (M. Emmet 
Walsh) to take photos of Ray and Abby in bed at a local motel. The morning after their tryst, Marty makes a menacing phone call to 
them, making it clear he is aware of their relationship.', 3.25, 5, 18)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Raising Arizona', 'Joel Coen', '1987-03-06', 'Criminal Herbert I. "Hi" McDunnough (Nicolas Cage) and policewoman Edwina "Ed" 
(Holly Hunter) meet after she takes the mugshots of the recidivist. With continued visits, Hi learns that Eds fiancé has left her. Hi 
proposes to her after his latest release from prison, and the two get married. They move into a desert mobile home, and Hi gets a job 
in a machine shop. They want to have children, but Ed discovers that she is infertile. Due to His criminal record, they cannot adopt a 
child. The couple learns of the "Arizona Quints," sons of locally famous furniture magnate Nathan Arizona (Trey Wilson); Hi and Ed 
kidnap one of the five babies, whom they believe to be Nathan Junior.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Barton Fink', 'Joel Coen', '1991-08-21', 'Barton Fink (John Turturro) is enjoying the success of his first Broadway play, Bare 
Ruined Choirs. His agent informs him that Capitol Pictures in Hollywood has offered a thousand dollars per week to write movie 
scripts. Barton hesitates, worried that moving to California would separate him from "the common man", his focus as a writer. He 
accepts the offer, however, and checks into the Hotel Earle, a large and unusually deserted building. His room is sparse and draped in 
subdued colors; its only decoration is a small painting of a woman on the beach, arm raised to block the sun.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Fargo', 'Joel Coen', '1996-03-08', 'In the winter of 1987, Minneapolis automobile salesman Jerry Lundegaard (Macy) is in financial 
trouble. Jerry is introduced to criminals Carl Showalter (Buscemi) and Gaear Grimsrud (Stormare) by Native American ex-convict 
Shep Proudfoot (Reevis), a mechanic at his dealership. Jerry travels to Fargo, North Dakota and hires the two men to kidnap his wife 
Jean (Rudrüd) in exchange for a new 1987 Oldsmobile Cutlass Ciera and half of the $80,000 ransom. However, Jerry intends to demand 
a much larger sum from his wealthy father-in-law Wade Gustafson (Presnell) and keep most of the money for himself.', 3.25, 5, 19)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('No Country for Old Men', 'Joel Coen', '2007-11-09', 'West Texas in June 1980 is desolate, wide open country, and Ed Tom Bell 
(Tommy Lee Jones) laments the increasing violence in a region where he, like his father and grandfather before him, has risen to the 
office of sheriff.', 4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Vanilla Sky', 'Cameron Crowe', '2001-12-14', 'David Aames (Tom Cruise) was the wealthy owner of a large publishing firm in New 
York City after the death of his father. From a prison cell, David, in a prosthetic mask, tells his story to psychiatrist Dr. Curtis McCabe 
(Kurt Russell): enjoying the bachelor lifestyle, he is introduced to Sofia Serrano (Penélope Cruz) by his best friend, Brian Shelby (Jason 
Lee), at a party. David and Sofia spend a night together talking, and fall in love. When Davids former girlfriend, Julianna "Julie" 
Gianni (Cameron Diaz), hears of Sofia, she attempts to kill herself and David in a car crash. While Julie dies, David remains alive, but 
his face is horribly disfigured, forcing him to wear a mask to hide the injuries. Unable to come to grips with the mask, he gets drunk 
on a night out at a bar with Sofia, and he is left to wallow in the street.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Narc', 'Joe Carnahan', '2003-01-10', 'Undercover narcotics officer Nick Tellis (Jason Patric) chases a drug dealer through the 
streets of Detroit after Tellis identity has been discovered. After the dealer fatally injects a bystander (whom Tellis was forced to 
leave behind) with drugs, he holds a young child hostage. Tellis manages to shoot and kill the dealer before he can hurt the child. 
However, one of the bullets inadvertently hits the childs pregnant mother, causing her to eventually miscarry.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Others', 'Alejandro Amenábar', '2001-08-10', 'Grace Stewart (Nicole Kidman) is a Catholic mother who lives with her two 
small children in a remote country house in the British Crown Dependency of Jersey, in the immediate aftermath of World War II. The 
children, Anne (Alakina Mann) and Nicholas (James Bentley), have an uncommon disease, xeroderma pigmentosa, characterized by 
photosensitivity, so their lives are structured around a series of complex rules designed to protect them from inadvertent exposure to 
sunlight.', 4.75, 3, 21)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Minority Report', 'Steven Spielberg', '2002-06-21', 'In April 2054, Captain John Anderton (Tom Cruise) is chief of the highly 
controversial Washington, D.C., PreCrime police force. They use future visions generated by three "precogs", mutated humans with 
precognitive abilities, to stop murders; because of this, the city has been murder-free for six years. Though Anderton is a respected 
member of the force, he is addicted to Clarity, an illegal psychoactive drug he began using after the disappearance of his son Sean. 
With the PreCrime force poised to go nationwide, the system is audited by Danny Witwer (Colin Farrell), a member of the United 
States Justice Department. During the audit, the precogs predict that Anderton will murder a man named Leo Crow in 36 hours. 
Believing the incident to be a setup by Witwer, who is aware of Andertons addiction, Anderton attempts to hide the case and quickly 
departs the area before Witwer begins a manhunt for him.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('War of the Worlds', 'Steven Spielberg', '2005-06-29', 'Ray Ferrier (Tom Cruise) is a container crane operator at a New Jersey 
port and is estranged from his children. He is visited by his ex-wife, Mary Ann (Miranda Otto), who drops off the children, Rachel 
(Dakota Fanning) and Robbie (Justin Chatwin), as she is going to visit her parents in Boston. Meanwhile T.V. reports tell of bizarre 
lightning storms which have knocked off power in parts of the Ukraine. Robbie takes Rays car out without his permission, so Ray 
starts searching for him. Outside, Ray notices a strange wall cloud, which starts to send out powerful lightning strikes, disabling all 
electronic devices in the area, including cars, forcing Robbie to come back. Ray heads down the street to investigate. He stops at a 
garage and tells Manny the local mechanic, to replace the solenoid on a dead car.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Last Samurai', 'The Last Samurai', '2003-12-05', 'In 1876, Captain Nathan Algren (Tom Cruise) is traumatized by his massacre 
of Native Americans in the Indian Wars and has become an alcoholic to stave off the memories. Algren is approached by former 
colleague Zebulon Gant (Billy Connolly), who takes him to meet Algrens former Colonel Bagley (Tony Goldwyn), whom Algren despises 
for ordering the massacre. On behalf of businessman Mr. Omura (Masato Harada), Bagley offers Algren a job training conscripts of the 
new Meiji government of Japan to suppress a samurai rebellion that is opposed to Western influence, led by Katsumoto (Ken Watanabe). 
Despite the painful ironies of crushing another tribal rebellion, Algren accepts solely for payment. In Japan he keeps a journal and is 
accompanied by British translator Simon Graham (Timothy Spall), who intends to write an account of Japanese culture, centering on 
the samurai.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Shattered Glass', 'Billy Ray', '2003-10-31', 'Stephen Randall Glass is a reporter/associate editor at The New Republic, a 
well-respected magazine located in Washington, DC., where he is making a name for himself for writing the most colorful stories. 
His editor, Michael Kelly, is revered by his young staff. When David Keene (at the time Chairman of the American Conservative Union) 
questions Glass description of minibars and the drunken antics of Young Republicans at a convention, Kelly backs his reporter when 
Glass admits to one mistake but says the rest is true.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Independence Day', 'Roland Emmerich', '1996-07-02', 'On July 2, an enormous alien ship enters Earths orbit and deploys 36 
smaller saucer-shaped ships, each 15 miles wide, which position themselves over major cities around the globe. David Levinson (Jeff 
Goldblum), a satellite technician for a television network in Manhattan, discovers transmissions hidden in satellite links that he 
realizes the aliens are using to coordinate an attack. David and his father Julius (Judd Hirsch) travel to the White House and warn his 
ex-wife, White House Communications Director Constance Spano (Margaret Colin), and President Thomas J. Whitmore (Bill Pullman) of 
the attack. The President, his daughter, portions of his Cabinet and the Levinsons narrowly escape aboard Air Force One as the alien 
spacecraft destroy Washington D.C., New York City, Los Angeles and other cities around the world.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Godzilla', 'Roland Emmerich', '1998-05-20', 'Following a nuclear incident in French Polynesia, a lizards nest is irradiated by the 
fallout of subsequent radiation. Decades later, a Japanese fishing vessel is suddenly attacked by an enormous sea creature in the 
South Pacific ocean; only one seaman survives. Traumatized, he is questioned by a mysterious Frenchman in a hospital regarding 
what he saw, to which he replies, "Gojira".', 3.25, 5, 24)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Patriot', 'Roland Emmerich', '2000-06-30', 'During the American Revolution in 1776, Benjamin Martin (Mel Gibson), a 
veteran of the French and Indian War and widower with seven children, is called to Charleston to vote in the South Carolina General 
Assembly on a levy supporting the Continental Army. Fearing war against Great Britain, Benjamin abstains. Captain James Wilkins 
(Adam Baldwin) votes against and joins the Loyalists. A supporting vote is nonetheless passed and against his fathers wishes, 
Benjamins eldest son Gabriel (Heath Ledger) joins the Continental Army.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Constantine', 'Francis Lawrence', '2005-02-18', 'John Constantine is an exorcist who lives in Los Angeles. Born with the power to 
see angels and demons on Earth, he committed suicide at age 15 after being unable to cope with his visions. Constantine was revived 
by paramedics but spent two minutes in Hell. He knows that because of his actions his soul is condemned to damnation when he dies, 
and has recently learned that he has developed cancer as a result of his smoking habit.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Shooter', 'Antoine Fuqua', '2007-03-23', 'Bob Lee Swagger (Mark Wahlberg) is a retired U.S. Marine Gunnery Sergeant who served 
as a Force Recon Scout Sniper. He reluctantly leaves a self-imposed exile from his isolated mountain home in the Wind River Range at 
the request of Colonel Isaac Johnson (Danny Glover). Johnson appeals to Swaggers expertise and patriotism to help track down an 
assassin who plans on shooting the president from a great distance with a high-powered rifle. Johnson gives him a list of three cities 
where the President is scheduled to visit so Swagger can determine if an attempt could be made at any of them.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Aviator', 'Martin Scorsese', '2004-12-25', 'In 1914, nine-year-old Howard Hughes is being bathed by his mother. She warns 
him of disease, afraid that he will succumb to a flu outbreak: "You are not safe." By 1927, Hughes (Leonardo DiCaprio) has inherited 
his familys fortune, is living in California. He hires Noah Dietrich (John C. Reilly) to run the Hughes Tool Company.', 4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The 11th Hour', 'Nadia Conners', '2007-08-17', 'With contributions from over 50 politicians, scientists, and environmental 
activists, including former Soviet leader Mikhail Gorbachev, physicist Stephen Hawking, Nobel Prize winner Wangari Maathai, and 
journalist Paul Hawken, the film documents the grave problems facing the planets life systems. Global warming, deforestation, mass 
species extinction, and depletion of the oceans habitats are all addressed. The films premise is that the future of humanity is in 
jeopardy.', 4.75, 3, 22)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Romancing the Stone', 'Robert Zemeckis', '1984-03-30', 'Joan Wilder (Kathleen Turner) is a lonely romance novelist in New York 
City who receives a treasure map mailed to her by her recently-murdered brother-in-law. Her widowed sister, Elaine (Mary Ellen 
Trainor), calls Joan and begs her to come to Cartagena, Colombia because Elaine has been kidnapped by bumbling antiquities 
smugglers Ira (Zack Norman) and Ralph (Danny DeVito), and the map is to be the ransom.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('One Flew Over the Cuckoos Nest', 'Miloš Forman', '1975-11-19', 'In 1963 Oregon, Randle Patrick "Mac" McMurphy (Jack Nicholson), 
a recidivist anti-authoritarian criminal serving a short sentence on a prison farm for statutory rape of a 15-year-old girl, is transferred 
to a mental institution for evaluation. Although he does not show any overt signs of mental illness, he hopes to avoid hard labor and 
serve the rest of his sentence in a more relaxed hospital environment.', 3.25, 5, 12)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Risky Business', 'Paul Brickman', '1983-08-05', 'Joel Goodson (Tom Cruise) is a high school student who lives with his wealthy 
parents in the North Shore area of suburban Chicago. His father wants him to attend Princeton University, so Joels mother tells him 
to tell the interviewer, Bill Rutherford, about his participation in Future Enterprisers, an extracurricular activity in which students 
work in teams to create small businesses.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Beetlejuice', 'Tim Burton', '1988-03-30', 'Barbara and Adam Maitland decide to spend their vacation decorating their idyllic New 
England country home in fictional Winter River, Connecticut. While the young couple are driving back from town, Barbara swerves to 
avoid a dog wandering the roadway and crashes through a covered bridge, plunging into the river below. They return home and, 
based on such subtle clues as their lack of reflection in the mirror and their discovery of a Handbook for the Recently Deceased, begin 
to suspect they might be dead. Adam attempts to leave the house to retrace his steps but finds himself in a strange, otherworldly 
dimension referred to as "Saturn", covered in sand and populated by enormous sandworms.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Hamlet 2', 'Andrew Fleming', '2008-08-22', 'Dana Marschz (Steve Coogan) is a recovering alcoholic and failed actor who has 
become a high school drama teacher in Tucson, Arizona, "where dreams go to die". Despite considering himself an inspirational figure, 
he only has two enthusiastic students, Rand (Skylar Astin) and Epiphany (Phoebe Strole), and a history of producing poorly-received 
school plays that are essentially stage adaptations of popular Hollywood films (his latest being Erin Brockovich). When the new term 
begins, a new intake of students are forced to transfer into his class as it is the only remaining arts elective available due to budget 
cutbacks; they are mostly unenthusiastic and unconvinced by Dana’s pretentions, and Dana comes into conflict with Octavio (Joseph 
Julian Soria), one of the new students.', 4.75, 3, 16)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Michael', 'Nora Ephron', '1996-12-25', 'Vartan Malt (Bob Hoskins) is the editor of a tabloid called the National Mirror that 
specializes in unlikely stories about celebrities and frankly unbelievable tales about ordinary folkspersons. When Malt gets word that a 
woman is supposedly harboring an angel in a small town in Iowa, he figures that this might be up the Mirrors alley, so he sends out 
three people to get the story – Frank Quinlan (William Hurt), a reporter whose career has hit the skids; Huey Driscoll (Robert Pastorelli), 
a photographer on the verge of losing his job (even though he owns the Mirrors mascot Sparky the Wonder Dog); and Dorothy Winters 
(Andie MacDowell), a self-styled "angel expert" (actually a dog trainer hired by Malt to eventually replace Driscoll).', 3.25, 5, 7)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Youve Got Mail', 'Nora Ephron', '1998-12-18', 'Kathleen Kelly (Meg Ryan) is involved with Frank Navasky (Greg Kinnear), a 
leftist postmodernist newspaper writer for the New York Observer whos always in search of an opportunity to root for the underdog. 
While Frank is devoted to his typewriter, Kathleen prefers her laptop and logging into her AOL e-mail account. There, using the screen 
name Shopgirl, she reads an e-mail from "NY152", the screen name of Joe Fox (Tom Hanks). In her reading of the e-mail, she reveals 
the boundaries of the online relationship; no specifics, including no names, career or class information, or family connections. Joe 
belongs to the Fox family which runs Fox Books — a chain of "mega" bookstores similar to Borders or Barnes & Noble.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bewitched', 'Nora Ephron', '2005-06-24', 'Jack Wyatt (Will Ferrell) is a narcissistic actor who is approached to play the role of 
Darrin in a remake of the classic sitcom Bewitched but insists that an unknown play Samantha.  Isabel Bigelow (Nicole Kidman) is an 
actual witch who decides she wants to be normal and moves to Los Angeles to start a new life and becomes friends with her neighbor 
Maria (Kristin Chenoweth). She goes to a bookstore to learn how to get a job after seeing an advertisement of Ed McMahon on TV.', 
4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Love Story', 'Arthur Hiller', '1970-12-16', 'The film tells of Oliver Barrett IV, who comes from a family of wealthy and 
well-respected Harvard University graduates. At Radcliffe library, the Harvard student meets and falls in love with Jennifer Cavalleri, 
a working-class, quick-witted Radcliffe College student. Upon graduation from college, the two decide to marry against the wishes of 
Olivers father, who thereupon severs ties with his son.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Godfather', 'Francis Ford Coppola', '1972-03-15', 'On the day of his only daughters wedding, Vito Corleone hears requests in 
his role as the Godfather, the Don of a New York crime family. Vitos youngest son, Michael, in Marine Corps khakis, introduces his 
girlfriend, Kay Adams, to his family at the sprawling reception. Vitos godson Johnny Fontane, a popular singer, pleads for help in 
securing a coveted movie role, so Vito dispatches his consigliere, Tom Hagen, to the abrasive studio head, Jack Woltz, to secure the 
casting. Woltz is unmoved until the morning he wakes up in bed with the severed head of his prized stallion.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Chinatown', 'Roman Polanski', '1974-06-20', 'A woman identifying herself as Evelyn Mulwray (Ladd) hires private investigator 
J.J. "Jake" Gittes (Nicholson) to perform matrimonial surveillance on her husband Hollis I. Mulwray (Zwerling), the chief engineer for 
the Los Angeles Department of Water and Power. Gittes tails him, hears him publicly oppose the creation of a new reservoir, and 
shoots photographs of him with a young woman (Palmer) that hit the front page of the following days paper. Upon his return to his 
office he is confronted by a beautiful woman who, after establishing that the two of them have never met, irately informs him that 
she is in fact Evelyn Mulwray (Dunaway) and he can expect a lawsuit.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Saint', 'Phillip Noyce', '1997-04-04', 'At the Saint Ignatius Orphanage, a rebellious boy named John Rossi refers to himself 
as "Simon Templar" and leads a group of fellow orphans as they attempt to run away to escape their harsh treatment. When Simon is 
caught by the head priest, he witnesses the tragic death of a girl he had taken a liking to when she accidentally falls from a balcony.', 
3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Alexander', 'Oliver Stone', '2004-11-24', 'The film is based on the life of Alexander the Great, King of Macedon, who conquered 
Asia Minor, Egypt, Persia and part of Ancient India. Shown are some of the key moments of Alexanders youth, his invasion of the 
mighty Persian Empire and his death. It also outlines his early life, including his difficult relationship with his father Philip II of 
Macedon, his strained feeling towards his mother Olympias, the unification of the Greek city-states and the two Greek Kingdoms 
(Macedon and Epirus) under the Hellenic League,[3] and the conquest of the Persian Empire in 331 BC. It also details his plans to 
reform his empire and the attempts he made to reach the end of the then known world.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Terminator Salvation', 'Joseph McGinty Nichol', '2009-05-21', 'In 2003, Doctor Serena Kogan (Helena Bonham Carter) of 
Cyberdyne Systems convinces death row inmate Marcus Wright (Sam Worthington) to sign his body over for medical research following 
his execution by lethal injection. One year later the Skynet system is activated, perceives humans as a threat to its own existence, 
and eradicates much of humanity in the event known as "Judgment Day" (as depicted in Terminator 3: Rise of the Machines).', 
4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('I Know What You Did Last Summer', 'Jim Gillespie', '1997-10-17', 'Four friends, Helen Shivers (Sarah Michelle Gellar), Julie 
James (Jennifer Love Hewitt), Barry Cox (Ryan Phillippe), and Ray Bronson (Freddie Prinze Jr.) go out of town to celebrate Helens 
winning the Miss Croaker pageant. Returning in Barrys new car, they hit and apparently kill a man, who is unknown to them. They 
dump the corpse in the ocean and agree to never discuss again what had happened.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Score', 'Frank Oz', '2001-07-13', 'After nearly being caught on a routine burglary, master safe-cracker Nick Wells (Robert De 
Niro) decides the time has finally come to retire. Nicks flight attendant girlfriend, Diane (Angela Bassett), encourages this decision, 
promising to fully commit to their relationship if he does indeed go straight. Nick, however, is lured into taking one final score by his 
fence Max (Marlon Brando) The job, worth a $4 million pay off to Nick, is to steal a valuable French sceptre, which was being smuggled 
illegally into the United States through Canada but was accidentally discovered and kept at the Montréal Customs House.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Sleepy Hollow', 'Tim Burton', '1999-11-19', 'In 1799, New York City, Ichabod Crane is a 24-year-old police officer. He is dispatched 
by his superiors to the Westchester County hamlet of Sleepy Hollow, New York, to investigate a series of brutal slayings in which the 
victims have been found decapitated: Peter Van Garrett, wealthy farmer and landowner; his son Dirk; and the widow Emily Winship, 
who secretly wed Van Garrett and was pregnant before being murdered. A pioneer of new, unproven forensic techniques such as 
finger-printing and autopsies, Crane arrives in Sleepy Hollow armed with his bag of scientific tools only to be informed by the towns 
elders that the murderer is not of flesh and blood, rather a headless undead Hessian mercenary from the American Revolutionary War 
who rides at night on a massive black steed in search of his missing head.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('I Still Know What You Did Last Summer', 'Danny Cannon', '1998-11-13', 'Julie James is getting over the events of the previous 
film, which nearly claimed her life. She hasnt been doing well in school and is continuously having nightmares involving Ben Willis 
(Muse Watson) still haunting her. Approaching the 4th July weekend, Ray (Freddie Prinze, Jr.) surprises her at her dorm. He invites 
her back up to Southport for the Croaker queen pageant. She objects and tells him she has not healed enough to go back. He tells her 
she needs some space away from Southport and him and leaves in a rush. After getting inside,she sits on her bed and looks at a picture 
of her deceased best friend Helen (Sarah Michelle Gellar), who died the previous summer at the hands of the fisherman.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard with a Vengeance', 'John McTiernan', '1995-05-19', 'In New York City, a bomb detonates destroying the Bonwit Teller 
department store. A man calling himself "Simon" phones Major Case Unit Inspector Walter Cobb of the New York City Police 
Department, claiming responsibility for the bomb. He demands that suspended police officer Lt. John McClane be dropped in Harlem 
wearing a sandwich board that says "I hate Niggers". Harlem shop owner Zeus Carver spots McClane and tries to get him off the street 
before he is killed, but a gang of black youths attack the pair, who barely escape. Returning to the station, they learn that Simon is 
believed to have stolen several thousand gallons of an explosive compound. Simon calls again demanding McClane and Carver put 
themselves through a series of "games" to prevent more explosions.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Terminator 3: Rise of the Machines', 'Jonathan Mostow', '2003-07-02', 'For nine years, John Connor (Nick Stahl) has been living 
off-the-grid in Los Angeles. Although Judgment Day did not occur on August 29, 1997, John does not believe that the prophesied war 
between humans and Skynet has been averted. Unable to locate John, Skynet sends a new model of Terminator, the T-X (Kristanna 
Loken), back in time to July 24, 2004 to kill his future lieutenants in the human Resistance. A more advanced model than previous 
Terminators, the T-X has an endoskeleton with built-in weaponry, a liquid metal exterior similar to the T-1000, and the ability to 
control other machines. The Resistance sends a reprogrammed T-850 model 101 Terminator (Arnold Schwarzenegger) back in time to 
protect the T-Xs targets, including Kate Brewster (Claire Danes) and John.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Amityville Horror', 'Andrew Douglas', '2005-04-15', 'On November 13, 1974, at 3:15am, Ronald DeFeo, Jr. shot and killed his 
family at their home, 112 Ocean Avenue in Amityville, New York. He killed five members of his family in their beds, but his youngest 
sister, Jodie, had been killed in her bedroom closet. He claimed that he was persuaded to kill them by voices he had heard in the 
house.', 4.75, 3, 21)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Runaway Bride', 'Garry Marshall', '1999-07-30', 'Maggie Carpenter (Julia Roberts) is a spirited and attractive young woman who 
has had a number of unsuccessful relationships. Maggie, nervous of being married, has left a trail of fiances. It seems, shes left three 
men waiting for her at the altar on their wedding day (all of which are caught on tape), receiving tabloid fame and the dubious 
nickname "The Runaway Bride".', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Jumanji', 'Joe Johnston', '1995-12-15', 'In 1869, two boys bury a chest in a forest near Keene, New Hampshire. A century later, 
12-year-old Alan Parrish flees from a gang of bullies to a shoe factory owned by his father, Sam, where he meets his friend Carl Bentley, 
one of Sams employees. When Alan accidentally damages a machine with a prototype sneaker Carl hopes to present, Carl takes the 
blame and loses his job. Outside the factory, after the bullies beat Alan up and steal his bicycle, Alan follows the sound of tribal 
drumbeats to a construction site and finds the chest, containing a board game called Jumanji.', 3.25, 5, 24)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Revenge of the Nerds', 'Jeff Kanew', '1984-07-20', 'Best friends and nerds Lewis Skolnick (Robert Carradine) and Gilbert Lowe 
(Anthony Edwards) enroll in Adams College to study computer science. The Alpha Betas, a fraternity to which many members of the 
schools football team belong, carelessly burn down their own house and seize the freshmen dorm for themselves. The college allows 
the displaced freshmen, living in the gymnasium, to join fraternities or move to other housing. Lewis, Gilbert, and other outcasts who 
cannot join a fraternity renovate a dilapidated home to serve as their own fraternity house.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Easy Rider', 'Dennis Hopper', '1969-07-14', 'The protagonists are two freewheeling hippies: Wyatt (Fonda), nicknamed "Captain 
America", and Billy (Hopper). Fonda and Hopper said that these characters names refer to Wyatt Earp and Billy the Kid.[4] Wyatt 
dresses in American flag-adorned leather (with an Office of the Secretary of Defense Identification Badge affixed to it), while Billy 
dresses in Native American-style buckskin pants and shirts and a bushman hat. The former is appreciative of help and of others, while 
the latter is often hostile and leery of outsiders.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Braveheart', 'Mel Gibson', '1995-05-24', 'In 1280, King Edward "Longshanks" (Patrick McGoohan) invades and conqueres Scotland 
following the death of Scotlands King Alexander III who left no heir to the throne. Young William Wallace witnesses the treachery of 
Longshanks, survives the death of his father and brother, and is taken abroad to Rome by his Uncle Argyle (Brian Cox) where he is 
educated.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Passion of the Christ', 'Mel Gibson', '2004-02-25', 'The film opens in Gethsemane as Jesus prays and is tempted by Satan, 
while his apostles, Peter, James and John sleep. After receiving thirty pieces of silver, one of Jesus other apostles, Judas, approaches 
with the temple guards and betrays Jesus with a kiss on the cheek. As the guards move in to arrest Jesus, Peter cuts off the ear of 
Malchus, but Jesus heals the ear. As the apostles flee, the temple guards arrest Jesus and beat him during the journey to the 
Sanhedrin. John tells Mary and Mary Magdalene of the arrest while Peter follows Jesus at a distance. Caiaphas holds trial over the 
objection of some of the other priests, who are expelled from the court.', 4.75, 3, 8)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Finding Neverland', 'Marc Forster', '2004-11-12', 'The story focuses on Scottish writer J. M. Barrie, his platonic relationship with 
Sylvia Llewelyn Davies, and his close friendship with her sons, who inspire the classic play Peter Pan, or The Boy Who Never Grew Up.', 
4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Bourne Identity', 'Doug Liman', '2002-06-14', 'In the Mediterranean Sea near Marseille, Italian fishermen rescue an 
unconscious man floating adrift with two gunshot wounds in his back. The boats medic finds a tiny laser projector surgically implanted 
under the unknown mans skin at the level of the hip. When activated, the laser projector displays the number of a safe deposit box in 
Zürich. The man wakes up and discovers he is suffering from extreme memory loss. Over the next few days on the ship, the man finds 
he is fluent in several languages and has unusual skills, but cannot remember anything about himself or why he was in the sea. When 
the ship docks, he sets off to investigate the safe deposit box.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Cider House Rules', 'Lasse Hallström', '1999-12-17', 'Homer Wells (Tobey Maguire), an orphan, is the films protagonist. He 
grew up in an orphanage directed by Dr. Wilbur Larch (Michael Caine) after being returned twice by foster parents. His first foster 
parents thought he was too quiet and the second parents beat him. Dr. Larch is addicted to ether and is also secretly an abortionist. 
Larch trains Homer in obstetrics and abortions as an apprentice, despite Homer never even having attended high school.', 3.25, 5, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Field of Dreams', 'Phil Alden Robinson', '1989-04-21', 'While walking in his cornfield, novice farmer Ray Kinsella hears a voice 
that whispers, "If you build it, he will come", and sees a baseball diamond. His wife, Annie, is skeptical, but she allows him to plow 
under his corn to build the field.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Waterworld', 'Kevin Reynolds', '1995-07-28', 'In the future (year 2500), the polar ice caps have melted due to the global warming, 
and the sea level has risen hundreds of meters, covering every continent and turning Earth into a water planet. Human population 
has been scattered across the ocean in individual, isolated communities consisting of artificial islands and mostly decrepit sea vessels. 
It was so long since the events that the humans eventually forgot that there were continents in the first place and that there is a 
place on Earth called "the Dryland", a mythical place.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard', 'John McTiernan', '1988-07-15', 'New York City Police Department detective John McClane arrives in Los Angeles to 
reconcile with his estranged wife, Holly. Limo driver Argyle drives McClane to the Nakatomi Plaza building to meet Holly at a company 
Christmas party. While McClane changes clothes, the party is disrupted by the arrival of German terrorist Hans Gruber and his heavily 
armed group: Karl, Franco, Tony, Theo, Alexander, Marco, Kristoff, Eddie, Uli, Heinrich, Fritz and James. The group seizes the 
skyscraper and secure those inside as hostages, except for McClane, who manages to slip away, armed with only his service sidearm, a 
Beretta 92F pistol.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard 2', 'Renny Harlin', '1990-07-04', 'On Christmas Eve, two years after the Nakatomi Tower Incident, John McClane is 
waiting at Washington Dulles International Airport for his wife Holly to arrive from Los Angeles, California. Reporter Richard Thornburg, 
who exposed Hollys identity to Hans Gruber in Die Hard, is assigned a seat across the aisle from her. While in the airport bar, McClane 
spots two men in army fatigues carrying a package; one of the men has a gun. Suspicious, he follows them into the baggage area. After 
a shootout, he kills one of the men while the other escapes. Learning the dead man is a mercenary thought to have been killed in 
action, McClane believes hes stumbled onto a nefarious plot. He relates his suspicions to airport police Captain Carmine Lorenzo, but 
Lorenzo refuses to listen and has McClane thrown out of his office.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Splash', 'Ron Howard', '1984-03-09', 'As an eight year-old boy, Allen Bauer (David Kreps) is vacationing with his family near Cape 
Cod. While taking a sight-seeing tour on a ferry, he gazes into the ocean and sees something below the surface that fascinates him. 
Allen jumps into the water, even though he cannot swim. He grasps the hands of a girl who is inexplicably under the water with him 
and an instant connection forms between the two. Allen is quickly pulled to the surface by the deck hands and the two are separated, 
though apparently no one else sees the girl. After the ferry moves off, Allen continues to look back at the girl in the water, who cries 
at their separation.', 3.25, 5, 25)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Parenthood', 'Ron Howard', '1989-08-02', 'Gil Buckman (Martin), a neurotic sales executive, is trying to balance his family and 
his career in suburban St. Louis. When he finds out that his eldest son, Kevin, has emotional problems and needs therapy, and that his 
two younger children, daughter Taylor and youngest son Justin, both have issues as well, he begins to blame himself and questions his 
abilities as a father. When his wife, Karen (Steenburgen), becomes pregnant with their fourth child, he is unsure he can handle it.', 
3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Apollo 13', 'Ron Howard', '1995-06-30', 'On July 20, 1969, veteran astronaut Jim Lovell (Tom Hanks) hosts a party for other 
astronauts and their families, who watch on television as their colleague Neil Armstrong takes his first steps on the Moon during the 
Apollo 11 mission. Lovell, who orbited the Moon on Apollo 8, tells his wife Marilyn (Kathleen Quinlan) that he intends to return, to 
walk on its surface.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Dr. Seuss How the Grinch Stole Christmas', 'Ron Howard', '2000-11-17', 'In the microscopic city of Whoville, everyone celebrates 
Christmas with much happiness and joy, with the exception of the cynical and misanthropic Grinch (Jim Carrey), who despises 
Christmas and the Whos with great wrath and occasionally pulls dangerous and harmful practical jokes on them. As a result, no one 
likes or cares for him.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('A Beautiful Mind', 'Ron Howard', '2001-12-21', 'In 1947, John Nash (Russell Crowe) arrives at Princeton University. He is co-recipient, 
with Martin Hansen (Josh Lucas), of the prestigious Carnegie Scholarship for mathematics. At a reception he meets a group of other 
promising math and science graduate students, Richard Sol (Adam Goldberg), Ainsley (Jason Gray-Stanford), and Bender (Anthony Rapp). 
He also meets his roommate Charles Herman (Paul Bettany), a literature student, and an unlikely friendship begins.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Da Vinci Code', 'Ron Howard', '2006-05-19', 'In Paris, Jacques Saunière is pursued through the Louvres Grand Gallery by 
albino monk Silas (Paul Bettany), demanding the Priorys clef de voûte or "keystone." Saunière confesses the keystone is kept in the 
sacristy of Church of Saint-Sulpice "beneath the Rose" before Silas shoots him. At the American University of Paris, Robert Langdon, a 
symbologist who is a guest lecturer on symbols and the sacred feminine, is summoned to the Louvre to view the crime scene. He 
discovers the dying Saunière has created an intricate display using black light ink and his own body and blood. Captain Bezu Fache 
(Jean Reno) asks him for his interpretation of the puzzling scene.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Simpsons Movie', 'David Silverman', '2007-07-27', 'While performing on Lake Springfield, rock band Green Day are killed 
when pollution in the lake dissolves their barge, following an audience revolt after frontman Billie Joe Armstrong proposes an 
environmental discussion. At a memorial service, Grampa has a prophetic vision in which he predicts the impending doom of the town, 
but only Marge takes it seriously. Then Homer dares Bart to skate naked and he does so. Lisa and an Irish boy named Colin, with whom 
she has fallen in love, hold a meeting where they convince the town to clean up the lake.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Crash', 'Paul Haggis', '2005-05-06', 'Los Angeles detectives Graham Waters (Don Cheadle) and his partner Ria (Jennifer Esposito) 
approach a crime scene investigation. Waters exits the car to check out the scene. One day prior, Farhad (Shaun Toub), a Persian 
shop owner, and his daughter, Dorri (Bahar Soomekh), argue with each other in front of a gun store owner as Farhad tries to buy a 
revolver. The shop keeper grows impatient and orders an infuriated Farhad outside. Dorri defiantly finishes the gun purchase, which 
she had opposed. The purchase entitles the buyer to one box of ammunition. She selects a red box.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Million Dollar Baby', 'Clint Eastwood', '2004-12-15', 'Margaret "Maggie" Fitzgerald, a waitress from a Missouri town in the Ozarks, 
shows up in the Hit Pit, a run-down Los Angeles gym which is owned and operated by Frankie Dunn, a brilliant but only marginally 
successful boxing trainer. Maggie asks Dunn to train her, but he angrily responds that he "doesnt train girls."', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Letters from Iwo Jima', 'Clint Eastwood', '2006-12-20', 'In 2005, Japanese archaeologists explore tunnels on Iwo Jima, where they 
find something buried in the soil.  The film flashes back to Iwo Jima in 1944. Private First Class Saigo is grudgingly digging trenches on 
the beach. A teenage baker, Saigo has been conscripted into the Imperial Japanese Army despite his youth and his wifes pregnancy. 
Saigo complains to his friend Private Kashiwara that they should let the Americans have Iwo Jima. Overhearing them, an enraged 
Captain Tanida starts brutally beating them for "conspiring with unpatriotic words." At the same time, General Tadamichi Kuribayashi 
arrives to take command of the garrison and immediately begins an inspection of the island defenses.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cast Away', 'Robert Zemeckis', '2000-12-07', 'In 1995, Chuck Noland (Tom Hanks) is a time-obsessed systems analyst, who travels 
worldwide resolving productivity problems at FedEx depots. He is in a long-term relationship with Kelly Frears (Helen Hunt), whom he 
lives with in Memphis, Tennessee. Although the couple wants to get married, Chucks busy schedule interferes with their relationship. 
A Christmas with relatives is interrupted by Chuck being summoned to resolve a problem in Malaysia.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cloverfield', 'J. J. Abrams', '2008-01-18', 'The film is presented as found footage from a personal video 
camera recovered by the United States Department of Defense. A disclaimer text states that the footage is of a case 
designated "Cloverfield" and was found in the area "formerly known as Central Park". The video consists chiefly of 
segments taped the night of Friday, May 22, 2009. The newer segments were taped over older video that is shown 
occasionally.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Mission: Impossible III', 'J. J. Abrams', '2006-05-05', 'Ethan Hunt (Tom Cruise) has retired from active field work for the 
Impossible Missions Force (IMF) and instead trains new recruits while settling down with his fiancée Julia Meade (Michelle Monaghan), 
a nurse at a local hospital who is unaware of Ethans past. Ethan is approached by fellow IMF agent John Musgrave (Billy Crudup) 
about a mission for him: rescue one of Ethans protégés, Lindsey Farris (Keri Russell), who was captured while investigating arms 
dealer Owen Davian (Philip Seymour Hoffman). Musgrave has already prepared a team for Ethan, consisting of Declan Gormley 
(Jonathan Rhys Meyers), Zhen Lei (Maggie Q), and his old partner Luther Stickell (Ving Rhames), in Berlin, Germany.', 4.75, 3, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Star Trek', 'J. J. Abrams', '2009-05-08', 'In 2233, the Federation starship USS Kelvin is investigating a "lightning storm" in space. 
A Romulan ship, the Narada, emerges from the storm and attacks the Kelvin. Naradas first officer, Ayel, demands that the Kelvins 
Captain Robau come aboard to discuss a cease fire. Once aboard, Robau is questioned about an "Ambassador Spock", who he states 
that he is "not familiar with", as well as the current stardate, after which the Naradas commander, Nero, flies into a rage and kills 
him, before continuing to attack the Kelvin. The Kelvins first officer, Lieutenant Commander George Kirk, orders the ships personnel 
evacuated via shuttlecraft, including his pregnant wife, Winona. Kirk steers the Kelvin on a collision course at the cost of his own life, 
while Winona gives birth to their son, James Tiberius Kirk.', 4.75, 3, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Halloween', 'John Carpenter', '1978-10-25', 'On Halloween night, 1963, in fictional Haddonfield, Illinois, 6-year-old Michael 
Myers (Will Sandin) murders his older teenage sister Judith (Sandy Johnson), stabbing her repeatedly with a butcher knife, after she 
had sex with her boyfriend. Fifteen years later, on October 30, 1978, Michael escapes the hospital in Smiths Grove, Illinois where he 
had been committed since the murder, stealing the car that was to take him to a court hearing.', 3.25, 5, 2)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Cable Guy', 'Ben Stiller', '1996-06-14', 'After a failed marriage proposal to his girlfriend Robin Harris (Leslie Mann), Steven 
M. Kovacs (Matthew Broderick) moves into his own apartment after they agree to spend some time apart. Enthusiastic cable guy 
Ernie "Chip" Douglas (Jim Carrey), an eccentric man with a lisp, installs his cable. Taking advice from his friend Rick (Jack Black), 
Steven bribes Chip to give him free movie channels, to which Chip agrees. Before he leaves, Chip gets Steven to hang out with him 
the next day and makes him one of his "preferred customers".', 3.25, 5, 3)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Anchorman: The Legend of Ron Burgundy', 'Adam McKay', '2004-07-09', 'In 1975, Ron Burgundy (Will Ferrell) is the famous and 
successful anchorman for San Diegos KVWN-TV Channel 4 Evening News. He works alongside his friends on the news team: 
fashion-oriented lead field reporter Brian Fantana (Paul Rudd), sportscaster Champion "Champ" Kind (David Koechner), and a "legally 
retarded" chief meteorologist Brick Tamland (Steve Carell). The team is notified by their boss, Ed Harken (Fred Willard), that their 
station has maintained its long-held status as the highest-rated news program in San Diego, leading them to throw a wild party. Ron 
sees an attractive blond woman and immediately tries to hit on her. After an awkward, failed pick-up attempt, the woman leaves.', 4.75, 3, 4) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The 40-Year-Old Virgin', 'Judd Apatow', '2005-08-19', 'Andy Stitzer (Steve Carell) is the eponymous 40-year-old virgin; he is 
involuntarily celibate. He lives alone, and is somewhat childlike; he collects action figures, plays video games, and his social life 
seems to consist of watching Survivor with his elderly neighbors. He works in the stockroom at an electronics store called SmartTech. 
When a friend drops out of a poker game, Andys co-workers David (Paul Rudd), Cal (Seth Rogen), and Jay (Romany Malco) reluctantly 
invite Andy to join them. At the game, when conversation turns to past sexual exploits, Andy desperately makes up a story, but when 
he compares the feel of a womans breast to a "bag of sand", he is forced to admit his virginity. Feeling sorry for him (but also 
generally mocking him), the group resolves to help Andy lose his virginity.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Knocked Up', 'Judd Apatow', '2007-06-01', 'Ben Stone (Seth Rogen) is laid-back and sardonic. He lives off funds received in 
compensation for an injury and sporadically works on a celebrity porn website with his roommates, in between smoking marijuana 
or going off with them at theme parks such as Knotts Berry Farm. Alison Scott (Katherine Heigl) is a career-minded woman who has 
just been given an on-air role with E! and is living in the pool house with her sister Debbies (Leslie Mann) family. While celebrating 
her promotion, Alison meets Ben at a local nightclub. After a night of drinking, they end up having sex. Due to a misunderstanding, 
they do not use protection: Alison uses the phrase "Just do it already" to encourage Ben to put the condom on, but he misinterprets 
this to mean to dispense with using one. The following morning, they quickly learn over breakfast that they have little in common 
and go their separate ways, which leaves Ben visibly upset.', 4.75, 3, 5) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Superbad', 'Greg Mottola', '2007-08-17', 'Seth (Jonah Hill) and Evan (Michael Cera) are two high school seniors who lament their 
virginity and poor social standing. Best friends since childhood, the two are about to go off to different colleges, as Seth did not get 
accepted into Dartmouth. After Seth is paired with Jules (Emma Stone) during Home-Ec class, she invites him to a party at her house 
later that night. Later, Fogell (Christopher Mintz-Plasse) comes up to the two and reveals his plans to obtain a fake ID during lunch. 
Seth uses this to his advantage and promises to bring alcohol to Jules party.', 4.75, 3, 3) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Donnie Darko', 'Richard Kelly', '2001-10-26', 'On October 2, 1988, Donnie Darko (Jake Gyllenhaal), a troubled teenager living in 
Middlesex, Virginia, is awakened and led outside by a figure in a monstrous rabbit costume, who introduces himself as "Frank" and 
tells him the world will end in 28 days, 6 hours, 42 minutes and 12 seconds. At dawn, Donnie awakens on a golf course and returns 
home to find a jet engine has crashed into his bedroom. His older sister, Elizabeth (Maggie Gyllenhaal), informs him the FAA 
investigators dont know where it came from.', 4.75, 3, 8)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Never Been Kissed', 'Raja Gosnell', '1999-04-09', 'Josie Geller (Drew Barrymore) is a copy editor for the Chicago Sun-Times who 
has never had a real relationship. One day during a staff meeting, the tyrannical editor-in-chief, Rigfort (Garry Marshall) assigns her 
to report undercover at a high school to help parents become more aware of their childrens lives.  Josie tells her brother Rob (David 
Arquette) about the assignment, and he reminds her that during high school she was a misfit labelled "Josie Grossie", a nickname 
which continues to haunt her.', 3.25, 5, 6)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Duplex', 'Danny DeVito', '2003-09-26', 'Alex Rose and Nancy Kendricks are a young, professional, New York couple in search of 
their dream home. When they finally find the perfect Brooklyn brownstone they are giddy with anticipation. The duplex is a dream 
come true, complete with multiple fireplaces, except for one thing: Mrs. Connelly, the old lady who lives on the rent-controlled top 
floor. Assuming she is elderly and ill, they take the apartment.', 4.75, 3, 9)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Music and Lyrics', 'Marc Lawrence', '2007-02-14', 'At the beginning of the film, Alex is a washed-up former pop star who is 
attempting to revive his career by hitching his career to the rising star of Cora Corman, a young megastar who has asked him to write 
a song titled "Way Back Into Love." During an unsuccessful attempt to come up with words for the song, he discovers that the woman 
who waters his plants, Sophie Fisher (Drew Barrymore), has a gift for writing lyrics. Sophie, a former creative writing student reeling 
from a disastrous romance with her former English professor Sloan Cates (Campbell Scott), initially refuses. Alex cajoles her into 
helping him by using a few quickly-chosen phrases she has given him as the basis for a song. Over the next few days, they grow closer 
while writing the words and music together, much to the delight of Sophies older sister Rhonda (Kristen Johnston), a huge fan of 
Alexs.', 4.75, 3, 10) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Charlies Angels', 'Joseph McGinty Nichol', '2000-11-03', 'Natalie Cook (Cameron Diaz), Dylan Sanders (Drew Barrymore) and 
Alex Munday (Lucy Liu) are the "Angels," three talented, tough, attractive women who work as private investigators for an unseen 
millionaire named Charlie (voiced by Forsythe). Charlie uses a speaker in his offices to communicate with the Angels, and his assistant 
Bosley (Bill Murray) works with them directly when needed.', 4.75, 3, 3)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Pulp Fiction', 'Quentin Tarantino', '1994-10-14', 'As Jules and Vincent eat breakfast in a coffee shop the discussion returns to 
Juless decision to retire. In a brief cutaway, we see "Pumpkin" and "Honey Bunny" shortly before they initiate the hold-up from the 
movies first scene. While Vincent is in the bathroom, the hold-up commences. "Pumpkin" demands all of the patrons valuables, 
including Juless mysterious case. Jules surprises "Pumpkin" (whom he calls "Ringo"), holding him at gunpoint. "Honey Bunny" (whose 
name turns out to be Yolanda), hysterical, trains her gun on Jules. Vincent emerges from the restroom with his gun trained on her, 
creating a Mexican standoff. Reprising his pseudo-biblical passage, Jules expresses his ambivalence about his life of crime.', 3.25, 5, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Kill Bill: Volume 1', 'Quentin Tarantino', '2003-10-03', '"The Bride", a former member of an assassination team who seeks 
revenge on her ex-colleagues who massacred members of her wedding party and tried to kill her. During the first movie she succeeds 
in killing two of the five members.', 4.75, 3, 9) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Kill Bill: Volume 2', 'Quentin Tarantino', '2004-04-16', '"The Bride", a former member of an assassination team who seeks 
revenge on her ex-colleagues who massacred members of her wedding party and tried to kill her. The film is often noted for its stylish 
direction and its homages to film genres such as Hong Kong martial arts films, Japanese chanbara films, Italian spaghetti westerns, 
girls with guns, and rape and revenge.', 4.75, 3, 9)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('An Inconvenient Truth', 'Davis Guggenheim', '2006-05-24', 'An Inconvenient Truth focuses on Al Gore and on his travels in 
support of his efforts to educate the public about the severity of the climate crisis. Gore says, "Ive been trying to tell this story for a 
long time and I feel as if Ive failed to get the message across."[6] The film documents a Keynote presentation (which Gore refers to 
as "the slide show") that Gore has presented throughout the world. It intersperses Gores exploration of data and predictions regarding 
climate change and its potential for disaster with his own life story.', 4.75, 3, 11)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Reservoir Dogs', 'Quentin Tarantino', '1992-10-23', 'Eight men eat breakfast at a Los Angeles diner before their planned diamond 
heist. Six of them use aliases: Mr. Blonde (Michael Madsen), Mr. Blue (Eddie Bunker), Mr. Brown (Quentin Tarantino), Mr. Orange (Tim 
Roth), Mr. Pink (Steve Buscemi), and Mr. White (Harvey Keitel). With them are gangster Joe Cabot (Lawrence Tierney), the organizer 
of the heist and his son, "Nice Guy" Eddie (Chris Penn).', 3.25, 5, 9)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Good Will Hunting', 'Gus Van Sant', '1997-12-05', '20-year-old Will Hunting (Matt Damon) of South Boston has a genius-level 
intellect but chooses to work as a janitor at the Massachusetts Institute of Technology and spend his free time with his friends Chuckie 
Sullivan (Ben Affleck), Billy McBride (Cole Hauser) and Morgan OMally (Casey Affleck). When Fields Medal-winning combinatorialist 
Professor Gerald Lambeau (Stellan Skarsgård) posts a difficult problem taken from algebraic graph theory as a challenge for his 
graduate students to solve, Will solves the problem quickly but anonymously. Lambeau posts a much more difficult problem and 
chances upon Will solving it, but Will flees. Will meets Skylar (Minnie Driver), a British student about to graduate from Harvard 
University and pursue a graduate degree at Stanford University School of Medicine in California.', 3.25, 5, 9) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Air Force One', 'Wolfgang Petersen', '1997-07-25', 'A joint military operation between Russian and American special operations 
forces ends with the capture of General Ivan Radek (Jürgen Prochnow), the dictator of a rogue terrorist regime in Kazakhstan that 
had taken possession of an arsenal of former Soviet nuclear weapons, who is now taken to a Russian maximum security prison. Three 
weeks later, a diplomatic dinner is held in Moscow to celebrate the capture of the Kazakh dictator, at which President of the United 
States James Marshall (Harrison Ford) expresses his remorse that action had not been taken sooner to prevent the suffering that 
Radek caused. He also vows that his administration will take a firmer stance against despotism and refuse to negotiate with terrorists.', 
3.25, 5, 3) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Hurricane', 'Norman Jewison', '1999-12-29', 'The film tells the story of middleweight boxer Rubin "Hurricane" Carter, whose 
conviction for a Paterson, New Jersey triple murder was set aside after he had spent almost 20 years in prison. Narrating Carters life, 
the film concentrates on the period between 1966 and 1985. It describes his fight against the conviction for triple murder and how he 
copes with nearly twenty years in prison. In a parallel plot, an underprivileged youth from Brooklyn, Lesra Martin, becomes interested 
in Carters life and destiny after reading Carters autobiography, and convinces his Canadian foster family to commit themselves to his 
case. The story culminates with Carters legal teams successful pleas to Judge H. Lee Sarokin of the United States District Court for 
the District of New Jersey.', 3.25, 5, 5)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Children of Men', 'Alfonso Cuarón', '2006-09-22', 'In 2027, after 18 years of worldwide female infertility, civilization is on the 
brink of collapse as humanity faces the grim reality of extinction. The United Kingdom, one of the few stable nations with a 
functioning government, has been deluged by asylum seekers from around the world, fleeing the chaos and war which has taken hold 
in most countries. In response, Britain has become a militarized police state as British forces round up and detain immigrants. 
Kidnapped by an immigrants rights group known as the Fishes, former activist turned cynical bureaucrat Theo Faron (Clive Owen) is 
brought to its leader, his estranged American wife Julian Taylor (Julianne Moore), from whom he separated after their son died from 
a flu pandemic in 2008.', 4.75, 3, 5)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bring It On', 'Peyton Reed', '2000-08-25', 'Torrance Shipman (Kirsten Dunst) anxiously dreams about her first day of senior year. 
Her boyfriend, Aaron (Richard Hillman), has left for college, and her cheerleading squad, the Toros, is aiming for a sixth consecutive 
national title. Team captain, "Big Red" (Lindsay Sloane), is graduating and Torrance is elected to take her place. Shortly after her 
election, however, a team member is injured and can no longer compete. Torrance replaces her with Missy Pantone (Eliza Dushku), 
a gymnast who recently transferred to the school with her brother, Cliff (Jesse Bradford). Torrance and Cliff develop a flirtatious 
friendship.', 4.75, 3, 5)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Elephant Man', 'David Lynch', '1980-10-03', 'London Hospital surgeon Frederick Treves discovers John Merrick in a Victorian 
freak show in Londons East End, where he is managed by the brutish Bytes. Merrick is deformed to the point that he must wear a hood 
and cap when in public, and Bytes claims he is an imbecile. Treves is professionally intrigued by Merricks condition and pays Bytes to 
bring him to the Hospital so that he can examine him. There, Treves presents Merrick to his colleagues in a lecture theatre, displaying 
him as a physiological curiosity. Treves draws attention to Merricks most life-threatening deformity, his abnormally large skull, which 
compels him to sleep with his head resting upon his knees, as the weight of his skull would asphyxiate him if he were to ever lie down. 
On Merricks return, Bytes beats him severely enough that a sympathetic apprentice alerts Treves, who returns him to the hospital. 
Bytes accuses Treves of likewise exploiting Merrick for his own ends, leading the surgeon to resolve to do what he can to help the 
unfortunate man.', 3.25, 5, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Fly', 'David Cronenberg', '1986-08-15', 'Seth Brundle (Jeff Goldblum), a brilliant but eccentric scientist, meets Veronica 
Quaife (Geena Davis), a journalist for Particle magazine, at a meet-the-press event held by Bartok Science Industries, the company 
that provides funding for Brundles work. Seth takes Veronica back to the warehouse that serves as both his home and laboratory, and 
shows her a project that will change the world: a set of "Telepods" that allows instantaneous teleportation of an object from one pod 
to another. Veronica eventually agrees to document Seths work. Although the Telepods can transport inanimate objects, they do not 
work properly on living things, as is demonstrated when a live baboon is turned inside-out during an experiment. Seth and Veronica 
begin a romantic relationship. Their first sexual encounter provides inspiration for Seth, who successfully reprograms the Telepod 
computer to cope with living creatures, and teleports a second baboon with no apparent harm.', 3.25, 5, 6) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Frances', 'Graeme Clifford', '1982-12-03', 'Born in Seattle, Washington, Frances Elena Farmer is a rebel from a young age, 
winning a high school award by writing an essay called "God Dies" in 1931. Later that decade, she becomes controversial again when 
she wins (and accepts) an all-expenses-paid trip to the USSR in 1935. Determined to become an actress, Frances is equally determined 
not to play the Hollywood game: she refuses to acquiesce to publicity stunts, and insists upon appearing on screen without makeup. 
Her defiance attracts the attention of Broadway playwright Clifford Odets, who convinces Frances that her future rests with the 
Group Theatre.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Young Frankenstein', 'Mel Brooks', '1974-12-15', 'Dr. Frederick Frankenstein (Gene Wilder) is a physician lecturer at an American 
medical school and engaged to the tightly wound Elizabeth (Madeline Kahn). He becomes exasperated when anyone brings up the 
subject of his grandfather, the infamous mad scientist. To disassociate himself from his legacy, Frederick insists that his surname be 
pronounced "Fronk-en-steen".', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Top Gun', 'Tony Scott', '1986-05-16', 'United States Naval Aviator Lieutenant Pete "Maverick" Mitchell (Tom Cruise) flies the 
F-14A Tomcat off USS Enterprise (CVN-65), with Radar Intercept Officer ("RIO") Lieutenant (Junior Grade) Nick "Goose" Bradshaw 
(Anthony Edwards). At the start of the film, wingman "Cougar" (John Stockwell) and his radar intercept officer "Merlin" (Tim Robbins), 
intercept MiG-28s over the Indian Ocean. During the engagement, one of the MiGs manages to get missile lock on Cougar. While 
Maverick realizes that the MiG "(would) have fired by now", if he really meant to fight, and drives off the MiGs, Cougar is too shaken 
afterward to land, despite being low on fuel. Maverick defies orders and shepherds Cougar back to the carrier, despite also being low 
on fuel. After they land, Cougar retires ("turns in his wings"), stating that he has been holding on "too tight" and has lost "the edge", 
almost orphaning his newborn child, whom he has never seen.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Crimson Tide', 'Tony Scott', '1995-05-12', 'In post-Soviet Russia, military units loyal to Vladimir Radchenko, an ultranationalist, 
have taken control of a nuclear missile installation and are threatening nuclear war if either the American or Russian governments 
attempt to confront him.', 3.25, 5, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Rock', 'Michael Bay', '1996-06-07', 'A group of rogue U.S. Force Recon Marines led by disenchanted Brigadier General Frank 
Hummel (Ed Harris) seize a stockpile of deadly VX gas–armed rockets from a heavily guarded US Navy bunker, reluctantly leaving one 
of their men to die in the process, when a bead of the gas falls and breaks. The next day, Hummel and his men, along with more 
renegade Marines Captains Frye (Gregory Sporleder) and Darrow (Tony Todd) (who have never previously served under Hummel) seize 
control of Alcatraz during a guided tour and take 81 tourists hostage in the prison cells. Hummel threatens to launch the stolen 
rockets against the population of San Francisco if the media is alerted or payment is refused or unless the government pays $100 
million in ransom and reparations to the families of Recon Marines, (using money the U.S. earned via illegal weapons sales) who died 
on illegal, clandestine missions under his command and whose deaths were not honored.', 3.25, 5, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Con Air', 'Simon West', '1997-06-06', 'Former U.S. Army Ranger Cameron Poe is sentenced to a maximum-security federal 
penitentiary for using excessive force and killing a drunk man who had been attempting to assault his pregnant wife, Tricia. Eight 
years later, Poe is paroled on good behavior, and eager to see his daughter Casey whom he has never met. Poe is arranged to be flown 
back home to Alabama on the C-123 Jailbird where he will be released on landing; several other prisoners, including his diabetic 
cellmate and friend Mike "Baby-O" ODell and criminal mastermind Cyrus "The Virus" Grissom, as well as Grissoms right-hand man, 
Nathan Jones, are also being transported to a new Supermax prison. DEA agent Duncan Malloy wishes to bring aboard one of his agents, 
Willie Sims, as a prisoner to coax more information out of drug lord Francisco Cindino before he is incarcerated. Vince Larkin, the U.S. 
Marshal overseeing the transfer, agrees to it, but is unaware that Malloy has armed Sims with a gun.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('National Treasure', 'Jon Turteltaub', '2004-11-19', 'Benjamin Franklin Gates (Nicolas Cage) is a historian and amateur cryptologist, 
and the youngest descendant of a long line of treasure hunters. Though Bens father, Patrick Henry Gates, tries to discourage Ben from 
following in the family line, as he had spent over 20 years looking for the national treasure, attracting ridicule on the family name, 
young Ben is encouraged onward by a clue, "The secret lies with Charlotte", from his grandfather John Adams Gates in 1974, that 
could lead to the fabled national treasure hidden by the Founding Fathers of the United States and Freemasons during the American 
Revolutionary War that was entrusted to his family by Charles Carroll of Carrollton in 1832 before his death to find, and protect the 
family name.', 4.75, 3, 15)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Hope Floats', 'Forest Whitaker', '1998-05-29', 'Birdee Pruitt (Sandra Bullock) is a Chicago housewife who is invited onto a talk 
show under the pretense of getting a free makeover. The makeover she is given is hardly what she has in mind...as she is ambushed 
with the revelation that her husband Bill has been having an affair behind her back with her best friend Connie. Humiliated on 
national television, Birdee and her daughter Bernice (Mae Whitman) move back to Birdees hometown of Smithville, Texas with 
Birdees eccentric mother Ramona (Gena Rowlands) to try to make a fresh start. As Birdee and Bernice leave Chicago, Birdee gives 
Bernice a letter from her father, telling Bernice how much he misses her.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Gun Shy', 'Eric Blakeney', '2000-02-04', 'Charlie Mayeaux (Liam Neeson) is an undercover DEA agent suffering from anxiety and 
gastrointestinal problems after a bust gone wrong. During the aforementioned incident, his partner was killed and he found himself 
served up on a platter of watermelon with a gun shoved in his face just before back-up arrived. Charlie, once known for his ease and 
almost "magical" talent on the job, is finding it very hard to return to work. His requests to be taken off the case or retired are denied 
by his bosses, Lonny Ward (Louis Giambalvo) and Dexter Helvenshaw (Mitch Pileggi) as so much time was put into his cover. Charlie 
works with the dream of one day retiring to Ocean Views, a luxury housing complex with servants and utilities.', 4.75, 3, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Miss Congeniality', 'Donald Petrie', '2000-12-22', 'The film opens at a school where a boy is picking on another boy. We see 
Gracie Hart (Mary Ashleigh Green) as a child who beats up the bully and tries to help the victim (whom she liked), who instead 
criticizes her by saying he disliked her because he did not want a girl to help him. She promptly punches the boy in the nose and sulks 
in the playground.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Murder by Numbers', 'Barbet Schroeder', '2002-04-19', 'Richard Haywood, a wealthy and popular high-schooler, secretly teams 
up with another rich kid in his class, brilliant nerd Justin "Bonaparte" Pendleton. His erudition, especially in forensic matters, allows 
them to plan elaborately perfect murders as a perverse form of entertainment. Meeting in a deserted resort, they drink absinthe, 
smoke, and joke around, but pretend to have an adversarial relationship while at school. Justin, in particular, behaves strangely, 
writing a paper about how crime is freedom and vice versa, and creating a composite photograph of himself and Richard.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Two Weeks Notice', 'Marc Lawrence', '2002-12-18', 'Lucy Kelson (Sandra Bullock) is a liberal lawyer who specializes in 
environmental law in New York City. George Wade (Hugh Grant) is an immature billionaire real estate tycoon who has almost 
everything and knows almost nothing. Lucys hard work and devotion to others contrast sharply with Georges world weary 
recklessness and greed.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Miss Congeniality 2: Armed and Fabulous', 'John Pasquin', '2005-03-24', 'Three weeks after the events of the first film, FBI agent 
Gracie Hart (Sandra Bullock) has become a celebrity after she infiltrated a beauty pageant on her last assignment. Her fame results in 
her cover being blown while she is trying to prevent a bank heist.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('All About Steve', 'Phil Traill', '2009-09-04', 'Mary Horowitz, a crossword puzzle writer for the Sacramento Herald, is socially 
awkward and considers her pet hamster her only true friend.  Her parents decide to set her up on a blind date. Marys expectations 
are low, as she tells her hamster. However, she is extremely surprised when her date turns out to be handsome and charming Steve 
Miller, a cameraman for the television news network CCN. However, her feelings for Steve are not reciprocated. After an attempt at 
an intimate moment fails, in part because of her awkwardness and inability to stop talking about vocabulary, Steve fakes a phone call 
about covering the news out of town. Trying to get Mary out of his truck, he tells her he wishes she could be there.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Nightmare Before Christmas', 'Henry Selick', '1993-10-29', 'Halloween Town is a dream world filled with citizens such as 
deformed monsters, ghosts, ghouls, goblins, vampires, werewolves and witches. Jack Skellington ("The Pumpkin King") leads them in a 
frightful celebration every Halloween, but he has grown tired of the same routine year after year. Wandering in the forest outside the 
town center, he accidentally opens a portal to "Christmas Town". Impressed by the feeling and style of Christmas, Jack presents his 
findings and his (somewhat limited) understanding of the festivities to the Halloween Town residents. They fail to grasp his meaning 
and compare everything he says to their idea of Halloween. He reluctantly decides to play along and announces that they will take 
over Christmas.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cabin Boy', 'Adam Resnick', '1994-01-07', 'Nathaniel Mayweather (Chris Elliott) is a snobbish, self-centered, virginal man. He is 
invited by his father to sail to Hawaii aboard the Queen Catherine. After annoying the driver, he is forced to walk the rest of the way.  
Nathaniel makes a wrong turn into a small fishing village where he meets the imbecilic cabin boy/first mate Kenny (Andy Richter). He 
thinks the ship, The Filthy Whore, is a theme boat. It is not until the next morning that Captain Greybar (Ritch Brinkley) finds 
Nathaniel in his room and explains that the boat will not return to dry land for three months.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('James and the Giant Peach', 'Henry Selick', '1996-04-12', 'In the 1930s, James Henry Trotter is a young boy who lives with his 
parents by the sea in the United Kingdom. On Jamess birthday, they plan to go to New York City and visit the Empire State Building, 
the tallest building in the world. However, his parents are later killed by a ghostly rhinoceros from the sky and finds himself living 
with his two cruel aunts, Spiker and Sponge.', 3.25, 5, 15)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('9', 'Shane Acker', '2009-09-09', 'Prior to the events of film, a scientist is ordered by his dictator to create a machine in the 
apparent name of progress. The Scientist uses his own intellect to create the B.R.A.I.N., a thinking robot. However, the dictator 
quickly seizes it and integrates it into the Fabrication Machine, an armature that can construct an army of war machines to destroy 
the dictators enemies. Lacking a soul, the Fabrication Machine is corrupted and exterminates all organic life using toxic gas. In 
desperation, the Scientist uses alchemy to create nine homunculus-like rag dolls known as Stitchpunks using portions of his own soul 
via a talisman, but dies as a result.', 4.75, 3, 16)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bruce Almighty', 'Tom Shadyac', '2003-05-23', 'Bruce Nolan (Jim Carrey) is a television field reporter for Eyewitness News on 
WKBW-TV in Buffalo, New York but desires to be the news anchorman. When he is passed over for the promotion in favour of his 
co-worker rival, Evan Baxter (Steve Carell), he becomes furious and rages during an interview at Niagara Falls, his resulting actions 
leading to his suspension from the station, followed by a series of misfortunes such as getting assaulted by a gang of thugs for standing 
up for a blind man they are beating up as he later on meets with them again and asks them to apologize for beating him up. Bruce 
complains to God that Hes "the one that should be fired".', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Fun with Dick and Jane', 'Dean Parisot', '2005-12-21', 'In January 2000, Dick Harper (Jim Carrey) has been promoted to VP of 
Communication for his company, Globodyne. Soon after, he is asked to appear on the show Money Life, where host Sam Samuels and 
then independent presidential candidate Ralph Nader dub him and all the companys employees as "perverters of the American dream" 
and claim that Globodyne helps the super rich get even wealthier. As they speak, the companys stock goes into a free-fall and is soon 
worthless, along with all the employees pensions, which are in Globodynes stock. Dick arrives home to find his excited wife Jane (Téa 
Leoni), who informs him that she took his advice and quit her job in order to spend more time with their son Billy.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Blood Simple', 'Joel Coen', '1985-01-18', 'Julian Marty (Dan Hedaya), the owner of a Texas bar, suspects his wife Abby (Frances 
McDormand) is having an affair with one of his bartenders, Ray (John Getz). Marty hires private detective Loren Visser (M. Emmet 
Walsh) to take photos of Ray and Abby in bed at a local motel. The morning after their tryst, Marty makes a menacing phone call to 
them, making it clear he is aware of their relationship.', 3.25, 5, 18)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Raising Arizona', 'Joel Coen', '1987-03-06', 'Criminal Herbert I. "Hi" McDunnough (Nicolas Cage) and policewoman Edwina "Ed" 
(Holly Hunter) meet after she takes the mugshots of the recidivist. With continued visits, Hi learns that Eds fiancé has left her. Hi 
proposes to her after his latest release from prison, and the two get married. They move into a desert mobile home, and Hi gets a job 
in a machine shop. They want to have children, but Ed discovers that she is infertile. Due to His criminal record, they cannot adopt a 
child. The couple learns of the "Arizona Quints," sons of locally famous furniture magnate Nathan Arizona (Trey Wilson); Hi and Ed 
kidnap one of the five babies, whom they believe to be Nathan Junior.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Barton Fink', 'Joel Coen', '1991-08-21', 'Barton Fink (John Turturro) is enjoying the success of his first Broadway play, Bare 
Ruined Choirs. His agent informs him that Capitol Pictures in Hollywood has offered a thousand dollars per week to write movie 
scripts. Barton hesitates, worried that moving to California would separate him from "the common man", his focus as a writer. He 
accepts the offer, however, and checks into the Hotel Earle, a large and unusually deserted building. His room is sparse and draped in 
subdued colors; its only decoration is a small painting of a woman on the beach, arm raised to block the sun.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Fargo', 'Joel Coen', '1996-03-08', 'In the winter of 1987, Minneapolis automobile salesman Jerry Lundegaard (Macy) is in financial 
trouble. Jerry is introduced to criminals Carl Showalter (Buscemi) and Gaear Grimsrud (Stormare) by Native American ex-convict 
Shep Proudfoot (Reevis), a mechanic at his dealership. Jerry travels to Fargo, North Dakota and hires the two men to kidnap his wife 
Jean (Rudrüd) in exchange for a new 1987 Oldsmobile Cutlass Ciera and half of the $80,000 ransom. However, Jerry intends to demand 
a much larger sum from his wealthy father-in-law Wade Gustafson (Presnell) and keep most of the money for himself.', 3.25, 5, 19)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('No Country for Old Men', 'Joel Coen', '2007-11-09', 'West Texas in June 1980 is desolate, wide open country, and Ed Tom Bell 
(Tommy Lee Jones) laments the increasing violence in a region where he, like his father and grandfather before him, has risen to the 
office of sheriff.', 4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Vanilla Sky', 'Cameron Crowe', '2001-12-14', 'David Aames (Tom Cruise) was the wealthy owner of a large publishing firm in New 
York City after the death of his father. From a prison cell, David, in a prosthetic mask, tells his story to psychiatrist Dr. Curtis McCabe 
(Kurt Russell): enjoying the bachelor lifestyle, he is introduced to Sofia Serrano (Penélope Cruz) by his best friend, Brian Shelby (Jason 
Lee), at a party. David and Sofia spend a night together talking, and fall in love. When Davids former girlfriend, Julianna "Julie" 
Gianni (Cameron Diaz), hears of Sofia, she attempts to kill herself and David in a car crash. While Julie dies, David remains alive, but 
his face is horribly disfigured, forcing him to wear a mask to hide the injuries. Unable to come to grips with the mask, he gets drunk 
on a night out at a bar with Sofia, and he is left to wallow in the street.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Narc', 'Joe Carnahan', '2003-01-10', 'Undercover narcotics officer Nick Tellis (Jason Patric) chases a drug dealer through the 
streets of Detroit after Tellis identity has been discovered. After the dealer fatally injects a bystander (whom Tellis was forced to 
leave behind) with drugs, he holds a young child hostage. Tellis manages to shoot and kill the dealer before he can hurt the child. 
However, one of the bullets inadvertently hits the childs pregnant mother, causing her to eventually miscarry.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Others', 'Alejandro Amenábar', '2001-08-10', 'Grace Stewart (Nicole Kidman) is a Catholic mother who lives with her two 
small children in a remote country house in the British Crown Dependency of Jersey, in the immediate aftermath of World War II. The 
children, Anne (Alakina Mann) and Nicholas (James Bentley), have an uncommon disease, xeroderma pigmentosa, characterized by 
photosensitivity, so their lives are structured around a series of complex rules designed to protect them from inadvertent exposure to 
sunlight.', 4.75, 3, 21)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Minority Report', 'Steven Spielberg', '2002-06-21', 'In April 2054, Captain John Anderton (Tom Cruise) is chief of the highly 
controversial Washington, D.C., PreCrime police force. They use future visions generated by three "precogs", mutated humans with 
precognitive abilities, to stop murders; because of this, the city has been murder-free for six years. Though Anderton is a respected 
member of the force, he is addicted to Clarity, an illegal psychoactive drug he began using after the disappearance of his son Sean. 
With the PreCrime force poised to go nationwide, the system is audited by Danny Witwer (Colin Farrell), a member of the United 
States Justice Department. During the audit, the precogs predict that Anderton will murder a man named Leo Crow in 36 hours. 
Believing the incident to be a setup by Witwer, who is aware of Andertons addiction, Anderton attempts to hide the case and quickly 
departs the area before Witwer begins a manhunt for him.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('War of the Worlds', 'Steven Spielberg', '2005-06-29', 'Ray Ferrier (Tom Cruise) is a container crane operator at a New Jersey 
port and is estranged from his children. He is visited by his ex-wife, Mary Ann (Miranda Otto), who drops off the children, Rachel 
(Dakota Fanning) and Robbie (Justin Chatwin), as she is going to visit her parents in Boston. Meanwhile T.V. reports tell of bizarre 
lightning storms which have knocked off power in parts of the Ukraine. Robbie takes Rays car out without his permission, so Ray 
starts searching for him. Outside, Ray notices a strange wall cloud, which starts to send out powerful lightning strikes, disabling all 
electronic devices in the area, including cars, forcing Robbie to come back. Ray heads down the street to investigate. He stops at a 
garage and tells Manny the local mechanic, to replace the solenoid on a dead car.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Last Samurai', 'The Last Samurai', '2003-12-05', 'In 1876, Captain Nathan Algren (Tom Cruise) is traumatized by his massacre 
of Native Americans in the Indian Wars and has become an alcoholic to stave off the memories. Algren is approached by former 
colleague Zebulon Gant (Billy Connolly), who takes him to meet Algrens former Colonel Bagley (Tony Goldwyn), whom Algren despises 
for ordering the massacre. On behalf of businessman Mr. Omura (Masato Harada), Bagley offers Algren a job training conscripts of the 
new Meiji government of Japan to suppress a samurai rebellion that is opposed to Western influence, led by Katsumoto (Ken Watanabe). 
Despite the painful ironies of crushing another tribal rebellion, Algren accepts solely for payment. In Japan he keeps a journal and is 
accompanied by British translator Simon Graham (Timothy Spall), who intends to write an account of Japanese culture, centering on 
the samurai.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Shattered Glass', 'Billy Ray', '2003-10-31', 'Stephen Randall Glass is a reporter/associate editor at The New Republic, a 
well-respected magazine located in Washington, DC., where he is making a name for himself for writing the most colorful stories. 
His editor, Michael Kelly, is revered by his young staff. When David Keene (at the time Chairman of the American Conservative Union) 
questions Glass description of minibars and the drunken antics of Young Republicans at a convention, Kelly backs his reporter when 
Glass admits to one mistake but says the rest is true.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Independence Day', 'Roland Emmerich', '1996-07-02', 'On July 2, an enormous alien ship enters Earths orbit and deploys 36 
smaller saucer-shaped ships, each 15 miles wide, which position themselves over major cities around the globe. David Levinson (Jeff 
Goldblum), a satellite technician for a television network in Manhattan, discovers transmissions hidden in satellite links that he 
realizes the aliens are using to coordinate an attack. David and his father Julius (Judd Hirsch) travel to the White House and warn his 
ex-wife, White House Communications Director Constance Spano (Margaret Colin), and President Thomas J. Whitmore (Bill Pullman) of 
the attack. The President, his daughter, portions of his Cabinet and the Levinsons narrowly escape aboard Air Force One as the alien 
spacecraft destroy Washington D.C., New York City, Los Angeles and other cities around the world.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Godzilla', 'Roland Emmerich', '1998-05-20', 'Following a nuclear incident in French Polynesia, a lizards nest is irradiated by the 
fallout of subsequent radiation. Decades later, a Japanese fishing vessel is suddenly attacked by an enormous sea creature in the 
South Pacific ocean; only one seaman survives. Traumatized, he is questioned by a mysterious Frenchman in a hospital regarding 
what he saw, to which he replies, "Gojira".', 3.25, 5, 24)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Patriot', 'Roland Emmerich', '2000-06-30', 'During the American Revolution in 1776, Benjamin Martin (Mel Gibson), a 
veteran of the French and Indian War and widower with seven children, is called to Charleston to vote in the South Carolina General 
Assembly on a levy supporting the Continental Army. Fearing war against Great Britain, Benjamin abstains. Captain James Wilkins 
(Adam Baldwin) votes against and joins the Loyalists. A supporting vote is nonetheless passed and against his fathers wishes, 
Benjamins eldest son Gabriel (Heath Ledger) joins the Continental Army.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Constantine', 'Francis Lawrence', '2005-02-18', 'John Constantine is an exorcist who lives in Los Angeles. Born with the power to 
see angels and demons on Earth, he committed suicide at age 15 after being unable to cope with his visions. Constantine was revived 
by paramedics but spent two minutes in Hell. He knows that because of his actions his soul is condemned to damnation when he dies, 
and has recently learned that he has developed cancer as a result of his smoking habit.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Shooter', 'Antoine Fuqua', '2007-03-23', 'Bob Lee Swagger (Mark Wahlberg) is a retired U.S. Marine Gunnery Sergeant who served 
as a Force Recon Scout Sniper. He reluctantly leaves a self-imposed exile from his isolated mountain home in the Wind River Range at 
the request of Colonel Isaac Johnson (Danny Glover). Johnson appeals to Swaggers expertise and patriotism to help track down an 
assassin who plans on shooting the president from a great distance with a high-powered rifle. Johnson gives him a list of three cities 
where the President is scheduled to visit so Swagger can determine if an attempt could be made at any of them.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Aviator', 'Martin Scorsese', '2004-12-25', 'In 1914, nine-year-old Howard Hughes is being bathed by his mother. She warns 
him of disease, afraid that he will succumb to a flu outbreak: "You are not safe." By 1927, Hughes (Leonardo DiCaprio) has inherited 
his familys fortune, is living in California. He hires Noah Dietrich (John C. Reilly) to run the Hughes Tool Company.', 4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The 11th Hour', 'Nadia Conners', '2007-08-17', 'With contributions from over 50 politicians, scientists, and environmental 
activists, including former Soviet leader Mikhail Gorbachev, physicist Stephen Hawking, Nobel Prize winner Wangari Maathai, and 
journalist Paul Hawken, the film documents the grave problems facing the planets life systems. Global warming, deforestation, mass 
species extinction, and depletion of the oceans habitats are all addressed. The films premise is that the future of humanity is in 
jeopardy.', 4.75, 3, 22)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Romancing the Stone', 'Robert Zemeckis', '1984-03-30', 'Joan Wilder (Kathleen Turner) is a lonely romance novelist in New York 
City who receives a treasure map mailed to her by her recently-murdered brother-in-law. Her widowed sister, Elaine (Mary Ellen 
Trainor), calls Joan and begs her to come to Cartagena, Colombia because Elaine has been kidnapped by bumbling antiquities 
smugglers Ira (Zack Norman) and Ralph (Danny DeVito), and the map is to be the ransom.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('One Flew Over the Cuckoos Nest', 'Miloš Forman', '1975-11-19', 'In 1963 Oregon, Randle Patrick "Mac" McMurphy (Jack Nicholson), 
a recidivist anti-authoritarian criminal serving a short sentence on a prison farm for statutory rape of a 15-year-old girl, is transferred 
to a mental institution for evaluation. Although he does not show any overt signs of mental illness, he hopes to avoid hard labor and 
serve the rest of his sentence in a more relaxed hospital environment.', 3.25, 5, 12)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Risky Business', 'Paul Brickman', '1983-08-05', 'Joel Goodson (Tom Cruise) is a high school student who lives with his wealthy 
parents in the North Shore area of suburban Chicago. His father wants him to attend Princeton University, so Joels mother tells him 
to tell the interviewer, Bill Rutherford, about his participation in Future Enterprisers, an extracurricular activity in which students 
work in teams to create small businesses.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Beetlejuice', 'Tim Burton', '1988-03-30', 'Barbara and Adam Maitland decide to spend their vacation decorating their idyllic New 
England country home in fictional Winter River, Connecticut. While the young couple are driving back from town, Barbara swerves to 
avoid a dog wandering the roadway and crashes through a covered bridge, plunging into the river below. They return home and, 
based on such subtle clues as their lack of reflection in the mirror and their discovery of a Handbook for the Recently Deceased, begin 
to suspect they might be dead. Adam attempts to leave the house to retrace his steps but finds himself in a strange, otherworldly 
dimension referred to as "Saturn", covered in sand and populated by enormous sandworms.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Hamlet 2', 'Andrew Fleming', '2008-08-22', 'Dana Marschz (Steve Coogan) is a recovering alcoholic and failed actor who has 
become a high school drama teacher in Tucson, Arizona, "where dreams go to die". Despite considering himself an inspirational figure, 
he only has two enthusiastic students, Rand (Skylar Astin) and Epiphany (Phoebe Strole), and a history of producing poorly-received 
school plays that are essentially stage adaptations of popular Hollywood films (his latest being Erin Brockovich). When the new term 
begins, a new intake of students are forced to transfer into his class as it is the only remaining arts elective available due to budget 
cutbacks; they are mostly unenthusiastic and unconvinced by Dana’s pretentions, and Dana comes into conflict with Octavio (Joseph 
Julian Soria), one of the new students.', 4.75, 3, 16)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Michael', 'Nora Ephron', '1996-12-25', 'Vartan Malt (Bob Hoskins) is the editor of a tabloid called the National Mirror that 
specializes in unlikely stories about celebrities and frankly unbelievable tales about ordinary folkspersons. When Malt gets word that a 
woman is supposedly harboring an angel in a small town in Iowa, he figures that this might be up the Mirrors alley, so he sends out 
three people to get the story – Frank Quinlan (William Hurt), a reporter whose career has hit the skids; Huey Driscoll (Robert Pastorelli), 
a photographer on the verge of losing his job (even though he owns the Mirrors mascot Sparky the Wonder Dog); and Dorothy Winters 
(Andie MacDowell), a self-styled "angel expert" (actually a dog trainer hired by Malt to eventually replace Driscoll).', 3.25, 5, 7)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Youve Got Mail', 'Nora Ephron', '1998-12-18', 'Kathleen Kelly (Meg Ryan) is involved with Frank Navasky (Greg Kinnear), a 
leftist postmodernist newspaper writer for the New York Observer whos always in search of an opportunity to root for the underdog. 
While Frank is devoted to his typewriter, Kathleen prefers her laptop and logging into her AOL e-mail account. There, using the screen 
name Shopgirl, she reads an e-mail from "NY152", the screen name of Joe Fox (Tom Hanks). In her reading of the e-mail, she reveals 
the boundaries of the online relationship; no specifics, including no names, career or class information, or family connections. Joe 
belongs to the Fox family which runs Fox Books — a chain of "mega" bookstores similar to Borders or Barnes & Noble.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bewitched', 'Nora Ephron', '2005-06-24', 'Jack Wyatt (Will Ferrell) is a narcissistic actor who is approached to play the role of 
Darrin in a remake of the classic sitcom Bewitched but insists that an unknown play Samantha.  Isabel Bigelow (Nicole Kidman) is an 
actual witch who decides she wants to be normal and moves to Los Angeles to start a new life and becomes friends with her neighbor 
Maria (Kristin Chenoweth). She goes to a bookstore to learn how to get a job after seeing an advertisement of Ed McMahon on TV.', 
4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Love Story', 'Arthur Hiller', '1970-12-16', 'The film tells of Oliver Barrett IV, who comes from a family of wealthy and 
well-respected Harvard University graduates. At Radcliffe library, the Harvard student meets and falls in love with Jennifer Cavalleri, 
a working-class, quick-witted Radcliffe College student. Upon graduation from college, the two decide to marry against the wishes of 
Olivers father, who thereupon severs ties with his son.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Godfather', 'Francis Ford Coppola', '1972-03-15', 'On the day of his only daughters wedding, Vito Corleone hears requests in 
his role as the Godfather, the Don of a New York crime family. Vitos youngest son, Michael, in Marine Corps khakis, introduces his 
girlfriend, Kay Adams, to his family at the sprawling reception. Vitos godson Johnny Fontane, a popular singer, pleads for help in 
securing a coveted movie role, so Vito dispatches his consigliere, Tom Hagen, to the abrasive studio head, Jack Woltz, to secure the 
casting. Woltz is unmoved until the morning he wakes up in bed with the severed head of his prized stallion.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Chinatown', 'Roman Polanski', '1974-06-20', 'A woman identifying herself as Evelyn Mulwray (Ladd) hires private investigator 
J.J. "Jake" Gittes (Nicholson) to perform matrimonial surveillance on her husband Hollis I. Mulwray (Zwerling), the chief engineer for 
the Los Angeles Department of Water and Power. Gittes tails him, hears him publicly oppose the creation of a new reservoir, and 
shoots photographs of him with a young woman (Palmer) that hit the front page of the following days paper. Upon his return to his 
office he is confronted by a beautiful woman who, after establishing that the two of them have never met, irately informs him that 
she is in fact Evelyn Mulwray (Dunaway) and he can expect a lawsuit.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Saint', 'Phillip Noyce', '1997-04-04', 'At the Saint Ignatius Orphanage, a rebellious boy named John Rossi refers to himself 
as "Simon Templar" and leads a group of fellow orphans as they attempt to run away to escape their harsh treatment. When Simon is 
caught by the head priest, he witnesses the tragic death of a girl he had taken a liking to when she accidentally falls from a balcony.', 
3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Alexander', 'Oliver Stone', '2004-11-24', 'The film is based on the life of Alexander the Great, King of Macedon, who conquered 
Asia Minor, Egypt, Persia and part of Ancient India. Shown are some of the key moments of Alexanders youth, his invasion of the 
mighty Persian Empire and his death. It also outlines his early life, including his difficult relationship with his father Philip II of 
Macedon, his strained feeling towards his mother Olympias, the unification of the Greek city-states and the two Greek Kingdoms 
(Macedon and Epirus) under the Hellenic League,[3] and the conquest of the Persian Empire in 331 BC. It also details his plans to 
reform his empire and the attempts he made to reach the end of the then known world.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Terminator Salvation', 'Joseph McGinty Nichol', '2009-05-21', 'In 2003, Doctor Serena Kogan (Helena Bonham Carter) of 
Cyberdyne Systems convinces death row inmate Marcus Wright (Sam Worthington) to sign his body over for medical research following 
his execution by lethal injection. One year later the Skynet system is activated, perceives humans as a threat to its own existence, 
and eradicates much of humanity in the event known as "Judgment Day" (as depicted in Terminator 3: Rise of the Machines).', 
4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('I Know What You Did Last Summer', 'Jim Gillespie', '1997-10-17', 'Four friends, Helen Shivers (Sarah Michelle Gellar), Julie 
James (Jennifer Love Hewitt), Barry Cox (Ryan Phillippe), and Ray Bronson (Freddie Prinze Jr.) go out of town to celebrate Helens 
winning the Miss Croaker pageant. Returning in Barrys new car, they hit and apparently kill a man, who is unknown to them. They 
dump the corpse in the ocean and agree to never discuss again what had happened.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Score', 'Frank Oz', '2001-07-13', 'After nearly being caught on a routine burglary, master safe-cracker Nick Wells (Robert De 
Niro) decides the time has finally come to retire. Nicks flight attendant girlfriend, Diane (Angela Bassett), encourages this decision, 
promising to fully commit to their relationship if he does indeed go straight. Nick, however, is lured into taking one final score by his 
fence Max (Marlon Brando) The job, worth a $4 million pay off to Nick, is to steal a valuable French sceptre, which was being smuggled 
illegally into the United States through Canada but was accidentally discovered and kept at the Montréal Customs House.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Sleepy Hollow', 'Tim Burton', '1999-11-19', 'In 1799, New York City, Ichabod Crane is a 24-year-old police officer. He is dispatched 
by his superiors to the Westchester County hamlet of Sleepy Hollow, New York, to investigate a series of brutal slayings in which the 
victims have been found decapitated: Peter Van Garrett, wealthy farmer and landowner; his son Dirk; and the widow Emily Winship, 
who secretly wed Van Garrett and was pregnant before being murdered. A pioneer of new, unproven forensic techniques such as 
finger-printing and autopsies, Crane arrives in Sleepy Hollow armed with his bag of scientific tools only to be informed by the towns 
elders that the murderer is not of flesh and blood, rather a headless undead Hessian mercenary from the American Revolutionary War 
who rides at night on a massive black steed in search of his missing head.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('I Still Know What You Did Last Summer', 'Danny Cannon', '1998-11-13', 'Julie James is getting over the events of the previous 
film, which nearly claimed her life. She hasnt been doing well in school and is continuously having nightmares involving Ben Willis 
(Muse Watson) still haunting her. Approaching the 4th July weekend, Ray (Freddie Prinze, Jr.) surprises her at her dorm. He invites 
her back up to Southport for the Croaker queen pageant. She objects and tells him she has not healed enough to go back. He tells her 
she needs some space away from Southport and him and leaves in a rush. After getting inside,she sits on her bed and looks at a picture 
of her deceased best friend Helen (Sarah Michelle Gellar), who died the previous summer at the hands of the fisherman.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard with a Vengeance', 'John McTiernan', '1995-05-19', 'In New York City, a bomb detonates destroying the Bonwit Teller 
department store. A man calling himself "Simon" phones Major Case Unit Inspector Walter Cobb of the New York City Police 
Department, claiming responsibility for the bomb. He demands that suspended police officer Lt. John McClane be dropped in Harlem 
wearing a sandwich board that says "I hate Niggers". Harlem shop owner Zeus Carver spots McClane and tries to get him off the street 
before he is killed, but a gang of black youths attack the pair, who barely escape. Returning to the station, they learn that Simon is 
believed to have stolen several thousand gallons of an explosive compound. Simon calls again demanding McClane and Carver put 
themselves through a series of "games" to prevent more explosions.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Terminator 3: Rise of the Machines', 'Jonathan Mostow', '2003-07-02', 'For nine years, John Connor (Nick Stahl) has been living 
off-the-grid in Los Angeles. Although Judgment Day did not occur on August 29, 1997, John does not believe that the prophesied war 
between humans and Skynet has been averted. Unable to locate John, Skynet sends a new model of Terminator, the T-X (Kristanna 
Loken), back in time to July 24, 2004 to kill his future lieutenants in the human Resistance. A more advanced model than previous 
Terminators, the T-X has an endoskeleton with built-in weaponry, a liquid metal exterior similar to the T-1000, and the ability to 
control other machines. The Resistance sends a reprogrammed T-850 model 101 Terminator (Arnold Schwarzenegger) back in time to 
protect the T-Xs targets, including Kate Brewster (Claire Danes) and John.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Amityville Horror', 'Andrew Douglas', '2005-04-15', 'On November 13, 1974, at 3:15am, Ronald DeFeo, Jr. shot and killed his 
family at their home, 112 Ocean Avenue in Amityville, New York. He killed five members of his family in their beds, but his youngest 
sister, Jodie, had been killed in her bedroom closet. He claimed that he was persuaded to kill them by voices he had heard in the 
house.', 4.75, 3, 21)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Runaway Bride', 'Garry Marshall', '1999-07-30', 'Maggie Carpenter (Julia Roberts) is a spirited and attractive young woman who 
has had a number of unsuccessful relationships. Maggie, nervous of being married, has left a trail of fiances. It seems, shes left three 
men waiting for her at the altar on their wedding day (all of which are caught on tape), receiving tabloid fame and the dubious 
nickname "The Runaway Bride".', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Jumanji', 'Joe Johnston', '1995-12-15', 'In 1869, two boys bury a chest in a forest near Keene, New Hampshire. A century later, 
12-year-old Alan Parrish flees from a gang of bullies to a shoe factory owned by his father, Sam, where he meets his friend Carl Bentley, 
one of Sams employees. When Alan accidentally damages a machine with a prototype sneaker Carl hopes to present, Carl takes the 
blame and loses his job. Outside the factory, after the bullies beat Alan up and steal his bicycle, Alan follows the sound of tribal 
drumbeats to a construction site and finds the chest, containing a board game called Jumanji.', 3.25, 5, 24)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Revenge of the Nerds', 'Jeff Kanew', '1984-07-20', 'Best friends and nerds Lewis Skolnick (Robert Carradine) and Gilbert Lowe 
(Anthony Edwards) enroll in Adams College to study computer science. The Alpha Betas, a fraternity to which many members of the 
schools football team belong, carelessly burn down their own house and seize the freshmen dorm for themselves. The college allows 
the displaced freshmen, living in the gymnasium, to join fraternities or move to other housing. Lewis, Gilbert, and other outcasts who 
cannot join a fraternity renovate a dilapidated home to serve as their own fraternity house.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Easy Rider', 'Dennis Hopper', '1969-07-14', 'The protagonists are two freewheeling hippies: Wyatt (Fonda), nicknamed "Captain 
America", and Billy (Hopper). Fonda and Hopper said that these characters names refer to Wyatt Earp and Billy the Kid.[4] Wyatt 
dresses in American flag-adorned leather (with an Office of the Secretary of Defense Identification Badge affixed to it), while Billy 
dresses in Native American-style buckskin pants and shirts and a bushman hat. The former is appreciative of help and of others, while 
the latter is often hostile and leery of outsiders.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Braveheart', 'Mel Gibson', '1995-05-24', 'In 1280, King Edward "Longshanks" (Patrick McGoohan) invades and conqueres Scotland 
following the death of Scotlands King Alexander III who left no heir to the throne. Young William Wallace witnesses the treachery of 
Longshanks, survives the death of his father and brother, and is taken abroad to Rome by his Uncle Argyle (Brian Cox) where he is 
educated.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Passion of the Christ', 'Mel Gibson', '2004-02-25', 'The film opens in Gethsemane as Jesus prays and is tempted by Satan, 
while his apostles, Peter, James and John sleep. After receiving thirty pieces of silver, one of Jesus other apostles, Judas, approaches 
with the temple guards and betrays Jesus with a kiss on the cheek. As the guards move in to arrest Jesus, Peter cuts off the ear of 
Malchus, but Jesus heals the ear. As the apostles flee, the temple guards arrest Jesus and beat him during the journey to the 
Sanhedrin. John tells Mary and Mary Magdalene of the arrest while Peter follows Jesus at a distance. Caiaphas holds trial over the 
objection of some of the other priests, who are expelled from the court.', 4.75, 3, 8)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Finding Neverland', 'Marc Forster', '2004-11-12', 'The story focuses on Scottish writer J. M. Barrie, his platonic relationship with 
Sylvia Llewelyn Davies, and his close friendship with her sons, who inspire the classic play Peter Pan, or The Boy Who Never Grew Up.', 
4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Bourne Identity', 'Doug Liman', '2002-06-14', 'In the Mediterranean Sea near Marseille, Italian fishermen rescue an 
unconscious man floating adrift with two gunshot wounds in his back. The boats medic finds a tiny laser projector surgically implanted 
under the unknown mans skin at the level of the hip. When activated, the laser projector displays the number of a safe deposit box in 
Zürich. The man wakes up and discovers he is suffering from extreme memory loss. Over the next few days on the ship, the man finds 
he is fluent in several languages and has unusual skills, but cannot remember anything about himself or why he was in the sea. When 
the ship docks, he sets off to investigate the safe deposit box.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Cider House Rules', 'Lasse Hallström', '1999-12-17', 'Homer Wells (Tobey Maguire), an orphan, is the films protagonist. He 
grew up in an orphanage directed by Dr. Wilbur Larch (Michael Caine) after being returned twice by foster parents. His first foster 
parents thought he was too quiet and the second parents beat him. Dr. Larch is addicted to ether and is also secretly an abortionist. 
Larch trains Homer in obstetrics and abortions as an apprentice, despite Homer never even having attended high school.', 3.25, 5, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Field of Dreams', 'Phil Alden Robinson', '1989-04-21', 'While walking in his cornfield, novice farmer Ray Kinsella hears a voice 
that whispers, "If you build it, he will come", and sees a baseball diamond. His wife, Annie, is skeptical, but she allows him to plow 
under his corn to build the field.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Waterworld', 'Kevin Reynolds', '1995-07-28', 'In the future (year 2500), the polar ice caps have melted due to the global warming, 
and the sea level has risen hundreds of meters, covering every continent and turning Earth into a water planet. Human population 
has been scattered across the ocean in individual, isolated communities consisting of artificial islands and mostly decrepit sea vessels. 
It was so long since the events that the humans eventually forgot that there were continents in the first place and that there is a 
place on Earth called "the Dryland", a mythical place.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard', 'John McTiernan', '1988-07-15', 'New York City Police Department detective John McClane arrives in Los Angeles to 
reconcile with his estranged wife, Holly. Limo driver Argyle drives McClane to the Nakatomi Plaza building to meet Holly at a company 
Christmas party. While McClane changes clothes, the party is disrupted by the arrival of German terrorist Hans Gruber and his heavily 
armed group: Karl, Franco, Tony, Theo, Alexander, Marco, Kristoff, Eddie, Uli, Heinrich, Fritz and James. The group seizes the 
skyscraper and secure those inside as hostages, except for McClane, who manages to slip away, armed with only his service sidearm, a 
Beretta 92F pistol.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard 2', 'Renny Harlin', '1990-07-04', 'On Christmas Eve, two years after the Nakatomi Tower Incident, John McClane is 
waiting at Washington Dulles International Airport for his wife Holly to arrive from Los Angeles, California. Reporter Richard Thornburg, 
who exposed Hollys identity to Hans Gruber in Die Hard, is assigned a seat across the aisle from her. While in the airport bar, McClane 
spots two men in army fatigues carrying a package; one of the men has a gun. Suspicious, he follows them into the baggage area. After 
a shootout, he kills one of the men while the other escapes. Learning the dead man is a mercenary thought to have been killed in 
action, McClane believes hes stumbled onto a nefarious plot. He relates his suspicions to airport police Captain Carmine Lorenzo, but 
Lorenzo refuses to listen and has McClane thrown out of his office.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Splash', 'Ron Howard', '1984-03-09', 'As an eight year-old boy, Allen Bauer (David Kreps) is vacationing with his family near Cape 
Cod. While taking a sight-seeing tour on a ferry, he gazes into the ocean and sees something below the surface that fascinates him. 
Allen jumps into the water, even though he cannot swim. He grasps the hands of a girl who is inexplicably under the water with him 
and an instant connection forms between the two. Allen is quickly pulled to the surface by the deck hands and the two are separated, 
though apparently no one else sees the girl. After the ferry moves off, Allen continues to look back at the girl in the water, who cries 
at their separation.', 3.25, 5, 25)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Parenthood', 'Ron Howard', '1989-08-02', 'Gil Buckman (Martin), a neurotic sales executive, is trying to balance his family and 
his career in suburban St. Louis. When he finds out that his eldest son, Kevin, has emotional problems and needs therapy, and that his 
two younger children, daughter Taylor and youngest son Justin, both have issues as well, he begins to blame himself and questions his 
abilities as a father. When his wife, Karen (Steenburgen), becomes pregnant with their fourth child, he is unsure he can handle it.', 
3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Apollo 13', 'Ron Howard', '1995-06-30', 'On July 20, 1969, veteran astronaut Jim Lovell (Tom Hanks) hosts a party for other 
astronauts and their families, who watch on television as their colleague Neil Armstrong takes his first steps on the Moon during the 
Apollo 11 mission. Lovell, who orbited the Moon on Apollo 8, tells his wife Marilyn (Kathleen Quinlan) that he intends to return, to 
walk on its surface.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Dr. Seuss How the Grinch Stole Christmas', 'Ron Howard', '2000-11-17', 'In the microscopic city of Whoville, everyone celebrates 
Christmas with much happiness and joy, with the exception of the cynical and misanthropic Grinch (Jim Carrey), who despises 
Christmas and the Whos with great wrath and occasionally pulls dangerous and harmful practical jokes on them. As a result, no one 
likes or cares for him.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('A Beautiful Mind', 'Ron Howard', '2001-12-21', 'In 1947, John Nash (Russell Crowe) arrives at Princeton University. He is co-recipient, 
with Martin Hansen (Josh Lucas), of the prestigious Carnegie Scholarship for mathematics. At a reception he meets a group of other 
promising math and science graduate students, Richard Sol (Adam Goldberg), Ainsley (Jason Gray-Stanford), and Bender (Anthony Rapp). 
He also meets his roommate Charles Herman (Paul Bettany), a literature student, and an unlikely friendship begins.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Da Vinci Code', 'Ron Howard', '2006-05-19', 'In Paris, Jacques Saunière is pursued through the Louvres Grand Gallery by 
albino monk Silas (Paul Bettany), demanding the Priorys clef de voûte or "keystone." Saunière confesses the keystone is kept in the 
sacristy of Church of Saint-Sulpice "beneath the Rose" before Silas shoots him. At the American University of Paris, Robert Langdon, a 
symbologist who is a guest lecturer on symbols and the sacred feminine, is summoned to the Louvre to view the crime scene. He 
discovers the dying Saunière has created an intricate display using black light ink and his own body and blood. Captain Bezu Fache 
(Jean Reno) asks him for his interpretation of the puzzling scene.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Simpsons Movie', 'David Silverman', '2007-07-27', 'While performing on Lake Springfield, rock band Green Day are killed 
when pollution in the lake dissolves their barge, following an audience revolt after frontman Billie Joe Armstrong proposes an 
environmental discussion. At a memorial service, Grampa has a prophetic vision in which he predicts the impending doom of the town, 
but only Marge takes it seriously. Then Homer dares Bart to skate naked and he does so. Lisa and an Irish boy named Colin, with whom 
she has fallen in love, hold a meeting where they convince the town to clean up the lake.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Crash', 'Paul Haggis', '2005-05-06', 'Los Angeles detectives Graham Waters (Don Cheadle) and his partner Ria (Jennifer Esposito) 
approach a crime scene investigation. Waters exits the car to check out the scene. One day prior, Farhad (Shaun Toub), a Persian 
shop owner, and his daughter, Dorri (Bahar Soomekh), argue with each other in front of a gun store owner as Farhad tries to buy a 
revolver. The shop keeper grows impatient and orders an infuriated Farhad outside. Dorri defiantly finishes the gun purchase, which 
she had opposed. The purchase entitles the buyer to one box of ammunition. She selects a red box.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Million Dollar Baby', 'Clint Eastwood', '2004-12-15', 'Margaret "Maggie" Fitzgerald, a waitress from a Missouri town in the Ozarks, 
shows up in the Hit Pit, a run-down Los Angeles gym which is owned and operated by Frankie Dunn, a brilliant but only marginally 
successful boxing trainer. Maggie asks Dunn to train her, but he angrily responds that he "doesnt train girls."', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Letters from Iwo Jima', 'Clint Eastwood', '2006-12-20', 'In 2005, Japanese archaeologists explore tunnels on Iwo Jima, where they 
find something buried in the soil.  The film flashes back to Iwo Jima in 1944. Private First Class Saigo is grudgingly digging trenches on 
the beach. A teenage baker, Saigo has been conscripted into the Imperial Japanese Army despite his youth and his wifes pregnancy. 
Saigo complains to his friend Private Kashiwara that they should let the Americans have Iwo Jima. Overhearing them, an enraged 
Captain Tanida starts brutally beating them for "conspiring with unpatriotic words." At the same time, General Tadamichi Kuribayashi 
arrives to take command of the garrison and immediately begins an inspection of the island defenses.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cast Away', 'Robert Zemeckis', '2000-12-07', 'In 1995, Chuck Noland (Tom Hanks) is a time-obsessed systems analyst, who travels 
worldwide resolving productivity problems at FedEx depots. He is in a long-term relationship with Kelly Frears (Helen Hunt), whom he 
lives with in Memphis, Tennessee. Although the couple wants to get married, Chucks busy schedule interferes with their relationship. 
A Christmas with relatives is interrupted by Chuck being summoned to resolve a problem in Malaysia.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cloverfield', 'J. J. Abrams', '2008-01-18', 'The film is presented as found footage from a personal video 
camera recovered by the United States Department of Defense. A disclaimer text states that the footage is of a case 
designated "Cloverfield" and was found in the area "formerly known as Central Park". The video consists chiefly of 
segments taped the night of Friday, May 22, 2009. The newer segments were taped over older video that is shown 
occasionally.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Mission: Impossible III', 'J. J. Abrams', '2006-05-05', 'Ethan Hunt (Tom Cruise) has retired from active field work for the 
Impossible Missions Force (IMF) and instead trains new recruits while settling down with his fiancée Julia Meade (Michelle Monaghan), 
a nurse at a local hospital who is unaware of Ethans past. Ethan is approached by fellow IMF agent John Musgrave (Billy Crudup) 
about a mission for him: rescue one of Ethans protégés, Lindsey Farris (Keri Russell), who was captured while investigating arms 
dealer Owen Davian (Philip Seymour Hoffman). Musgrave has already prepared a team for Ethan, consisting of Declan Gormley 
(Jonathan Rhys Meyers), Zhen Lei (Maggie Q), and his old partner Luther Stickell (Ving Rhames), in Berlin, Germany.', 4.75, 3, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Star Trek', 'J. J. Abrams', '2009-05-08', 'In 2233, the Federation starship USS Kelvin is investigating a "lightning storm" in space. 
A Romulan ship, the Narada, emerges from the storm and attacks the Kelvin. Naradas first officer, Ayel, demands that the Kelvins 
Captain Robau come aboard to discuss a cease fire. Once aboard, Robau is questioned about an "Ambassador Spock", who he states 
that he is "not familiar with", as well as the current stardate, after which the Naradas commander, Nero, flies into a rage and kills 
him, before continuing to attack the Kelvin. The Kelvins first officer, Lieutenant Commander George Kirk, orders the ships personnel 
evacuated via shuttlecraft, including his pregnant wife, Winona. Kirk steers the Kelvin on a collision course at the cost of his own life, 
while Winona gives birth to their son, James Tiberius Kirk.', 4.75, 3, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Halloween', 'John Carpenter', '1978-10-25', 'On Halloween night, 1963, in fictional Haddonfield, Illinois, 6-year-old Michael 
Myers (Will Sandin) murders his older teenage sister Judith (Sandy Johnson), stabbing her repeatedly with a butcher knife, after she 
had sex with her boyfriend. Fifteen years later, on October 30, 1978, Michael escapes the hospital in Smiths Grove, Illinois where he 
had been committed since the murder, stealing the car that was to take him to a court hearing.', 3.25, 5, 2)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Cable Guy', 'Ben Stiller', '1996-06-14', 'After a failed marriage proposal to his girlfriend Robin Harris (Leslie Mann), Steven 
M. Kovacs (Matthew Broderick) moves into his own apartment after they agree to spend some time apart. Enthusiastic cable guy 
Ernie "Chip" Douglas (Jim Carrey), an eccentric man with a lisp, installs his cable. Taking advice from his friend Rick (Jack Black), 
Steven bribes Chip to give him free movie channels, to which Chip agrees. Before he leaves, Chip gets Steven to hang out with him 
the next day and makes him one of his "preferred customers".', 3.25, 5, 3)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Anchorman: The Legend of Ron Burgundy', 'Adam McKay', '2004-07-09', 'In 1975, Ron Burgundy (Will Ferrell) is the famous and 
successful anchorman for San Diegos KVWN-TV Channel 4 Evening News. He works alongside his friends on the news team: 
fashion-oriented lead field reporter Brian Fantana (Paul Rudd), sportscaster Champion "Champ" Kind (David Koechner), and a "legally 
retarded" chief meteorologist Brick Tamland (Steve Carell). The team is notified by their boss, Ed Harken (Fred Willard), that their 
station has maintained its long-held status as the highest-rated news program in San Diego, leading them to throw a wild party. Ron 
sees an attractive blond woman and immediately tries to hit on her. After an awkward, failed pick-up attempt, the woman leaves.', 4.75, 3, 4) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The 40-Year-Old Virgin', 'Judd Apatow', '2005-08-19', 'Andy Stitzer (Steve Carell) is the eponymous 40-year-old virgin; he is 
involuntarily celibate. He lives alone, and is somewhat childlike; he collects action figures, plays video games, and his social life 
seems to consist of watching Survivor with his elderly neighbors. He works in the stockroom at an electronics store called SmartTech. 
When a friend drops out of a poker game, Andys co-workers David (Paul Rudd), Cal (Seth Rogen), and Jay (Romany Malco) reluctantly 
invite Andy to join them. At the game, when conversation turns to past sexual exploits, Andy desperately makes up a story, but when 
he compares the feel of a womans breast to a "bag of sand", he is forced to admit his virginity. Feeling sorry for him (but also 
generally mocking him), the group resolves to help Andy lose his virginity.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Knocked Up', 'Judd Apatow', '2007-06-01', 'Ben Stone (Seth Rogen) is laid-back and sardonic. He lives off funds received in 
compensation for an injury and sporadically works on a celebrity porn website with his roommates, in between smoking marijuana 
or going off with them at theme parks such as Knotts Berry Farm. Alison Scott (Katherine Heigl) is a career-minded woman who has 
just been given an on-air role with E! and is living in the pool house with her sister Debbies (Leslie Mann) family. While celebrating 
her promotion, Alison meets Ben at a local nightclub. After a night of drinking, they end up having sex. Due to a misunderstanding, 
they do not use protection: Alison uses the phrase "Just do it already" to encourage Ben to put the condom on, but he misinterprets 
this to mean to dispense with using one. The following morning, they quickly learn over breakfast that they have little in common 
and go their separate ways, which leaves Ben visibly upset.', 4.75, 3, 5) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Superbad', 'Greg Mottola', '2007-08-17', 'Seth (Jonah Hill) and Evan (Michael Cera) are two high school seniors who lament their 
virginity and poor social standing. Best friends since childhood, the two are about to go off to different colleges, as Seth did not get 
accepted into Dartmouth. After Seth is paired with Jules (Emma Stone) during Home-Ec class, she invites him to a party at her house 
later that night. Later, Fogell (Christopher Mintz-Plasse) comes up to the two and reveals his plans to obtain a fake ID during lunch. 
Seth uses this to his advantage and promises to bring alcohol to Jules party.', 4.75, 3, 3) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Donnie Darko', 'Richard Kelly', '2001-10-26', 'On October 2, 1988, Donnie Darko (Jake Gyllenhaal), a troubled teenager living in 
Middlesex, Virginia, is awakened and led outside by a figure in a monstrous rabbit costume, who introduces himself as "Frank" and 
tells him the world will end in 28 days, 6 hours, 42 minutes and 12 seconds. At dawn, Donnie awakens on a golf course and returns 
home to find a jet engine has crashed into his bedroom. His older sister, Elizabeth (Maggie Gyllenhaal), informs him the FAA 
investigators dont know where it came from.', 4.75, 3, 8)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Never Been Kissed', 'Raja Gosnell', '1999-04-09', 'Josie Geller (Drew Barrymore) is a copy editor for the Chicago Sun-Times who 
has never had a real relationship. One day during a staff meeting, the tyrannical editor-in-chief, Rigfort (Garry Marshall) assigns her 
to report undercover at a high school to help parents become more aware of their childrens lives.  Josie tells her brother Rob (David 
Arquette) about the assignment, and he reminds her that during high school she was a misfit labelled "Josie Grossie", a nickname 
which continues to haunt her.', 3.25, 5, 6)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Duplex', 'Danny DeVito', '2003-09-26', 'Alex Rose and Nancy Kendricks are a young, professional, New York couple in search of 
their dream home. When they finally find the perfect Brooklyn brownstone they are giddy with anticipation. The duplex is a dream 
come true, complete with multiple fireplaces, except for one thing: Mrs. Connelly, the old lady who lives on the rent-controlled top 
floor. Assuming she is elderly and ill, they take the apartment.', 4.75, 3, 9)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Music and Lyrics', 'Marc Lawrence', '2007-02-14', 'At the beginning of the film, Alex is a washed-up former pop star who is 
attempting to revive his career by hitching his career to the rising star of Cora Corman, a young megastar who has asked him to write 
a song titled "Way Back Into Love." During an unsuccessful attempt to come up with words for the song, he discovers that the woman 
who waters his plants, Sophie Fisher (Drew Barrymore), has a gift for writing lyrics. Sophie, a former creative writing student reeling 
from a disastrous romance with her former English professor Sloan Cates (Campbell Scott), initially refuses. Alex cajoles her into 
helping him by using a few quickly-chosen phrases she has given him as the basis for a song. Over the next few days, they grow closer 
while writing the words and music together, much to the delight of Sophies older sister Rhonda (Kristen Johnston), a huge fan of 
Alexs.', 4.75, 3, 10) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Charlies Angels', 'Joseph McGinty Nichol', '2000-11-03', 'Natalie Cook (Cameron Diaz), Dylan Sanders (Drew Barrymore) and 
Alex Munday (Lucy Liu) are the "Angels," three talented, tough, attractive women who work as private investigators for an unseen 
millionaire named Charlie (voiced by Forsythe). Charlie uses a speaker in his offices to communicate with the Angels, and his assistant 
Bosley (Bill Murray) works with them directly when needed.', 4.75, 3, 3)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Pulp Fiction', 'Quentin Tarantino', '1994-10-14', 'As Jules and Vincent eat breakfast in a coffee shop the discussion returns to 
Juless decision to retire. In a brief cutaway, we see "Pumpkin" and "Honey Bunny" shortly before they initiate the hold-up from the 
movies first scene. While Vincent is in the bathroom, the hold-up commences. "Pumpkin" demands all of the patrons valuables, 
including Juless mysterious case. Jules surprises "Pumpkin" (whom he calls "Ringo"), holding him at gunpoint. "Honey Bunny" (whose 
name turns out to be Yolanda), hysterical, trains her gun on Jules. Vincent emerges from the restroom with his gun trained on her, 
creating a Mexican standoff. Reprising his pseudo-biblical passage, Jules expresses his ambivalence about his life of crime.', 3.25, 5, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Kill Bill: Volume 1', 'Quentin Tarantino', '2003-10-03', '"The Bride", a former member of an assassination team who seeks 
revenge on her ex-colleagues who massacred members of her wedding party and tried to kill her. During the first movie she succeeds 
in killing two of the five members.', 4.75, 3, 9) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Kill Bill: Volume 2', 'Quentin Tarantino', '2004-04-16', '"The Bride", a former member of an assassination team who seeks 
revenge on her ex-colleagues who massacred members of her wedding party and tried to kill her. The film is often noted for its stylish 
direction and its homages to film genres such as Hong Kong martial arts films, Japanese chanbara films, Italian spaghetti westerns, 
girls with guns, and rape and revenge.', 4.75, 3, 9)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('An Inconvenient Truth', 'Davis Guggenheim', '2006-05-24', 'An Inconvenient Truth focuses on Al Gore and on his travels in 
support of his efforts to educate the public about the severity of the climate crisis. Gore says, "Ive been trying to tell this story for a 
long time and I feel as if Ive failed to get the message across."[6] The film documents a Keynote presentation (which Gore refers to 
as "the slide show") that Gore has presented throughout the world. It intersperses Gores exploration of data and predictions regarding 
climate change and its potential for disaster with his own life story.', 4.75, 3, 11)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Reservoir Dogs', 'Quentin Tarantino', '1992-10-23', 'Eight men eat breakfast at a Los Angeles diner before their planned diamond 
heist. Six of them use aliases: Mr. Blonde (Michael Madsen), Mr. Blue (Eddie Bunker), Mr. Brown (Quentin Tarantino), Mr. Orange (Tim 
Roth), Mr. Pink (Steve Buscemi), and Mr. White (Harvey Keitel). With them are gangster Joe Cabot (Lawrence Tierney), the organizer 
of the heist and his son, "Nice Guy" Eddie (Chris Penn).', 3.25, 5, 9)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Good Will Hunting', 'Gus Van Sant', '1997-12-05', '20-year-old Will Hunting (Matt Damon) of South Boston has a genius-level 
intellect but chooses to work as a janitor at the Massachusetts Institute of Technology and spend his free time with his friends Chuckie 
Sullivan (Ben Affleck), Billy McBride (Cole Hauser) and Morgan OMally (Casey Affleck). When Fields Medal-winning combinatorialist 
Professor Gerald Lambeau (Stellan Skarsgård) posts a difficult problem taken from algebraic graph theory as a challenge for his 
graduate students to solve, Will solves the problem quickly but anonymously. Lambeau posts a much more difficult problem and 
chances upon Will solving it, but Will flees. Will meets Skylar (Minnie Driver), a British student about to graduate from Harvard 
University and pursue a graduate degree at Stanford University School of Medicine in California.', 3.25, 5, 9) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Air Force One', 'Wolfgang Petersen', '1997-07-25', 'A joint military operation between Russian and American special operations 
forces ends with the capture of General Ivan Radek (Jürgen Prochnow), the dictator of a rogue terrorist regime in Kazakhstan that 
had taken possession of an arsenal of former Soviet nuclear weapons, who is now taken to a Russian maximum security prison. Three 
weeks later, a diplomatic dinner is held in Moscow to celebrate the capture of the Kazakh dictator, at which President of the United 
States James Marshall (Harrison Ford) expresses his remorse that action had not been taken sooner to prevent the suffering that 
Radek caused. He also vows that his administration will take a firmer stance against despotism and refuse to negotiate with terrorists.', 
3.25, 5, 3) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Hurricane', 'Norman Jewison', '1999-12-29', 'The film tells the story of middleweight boxer Rubin "Hurricane" Carter, whose 
conviction for a Paterson, New Jersey triple murder was set aside after he had spent almost 20 years in prison. Narrating Carters life, 
the film concentrates on the period between 1966 and 1985. It describes his fight against the conviction for triple murder and how he 
copes with nearly twenty years in prison. In a parallel plot, an underprivileged youth from Brooklyn, Lesra Martin, becomes interested 
in Carters life and destiny after reading Carters autobiography, and convinces his Canadian foster family to commit themselves to his 
case. The story culminates with Carters legal teams successful pleas to Judge H. Lee Sarokin of the United States District Court for 
the District of New Jersey.', 3.25, 5, 5)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Children of Men', 'Alfonso Cuarón', '2006-09-22', 'In 2027, after 18 years of worldwide female infertility, civilization is on the 
brink of collapse as humanity faces the grim reality of extinction. The United Kingdom, one of the few stable nations with a 
functioning government, has been deluged by asylum seekers from around the world, fleeing the chaos and war which has taken hold 
in most countries. In response, Britain has become a militarized police state as British forces round up and detain immigrants. 
Kidnapped by an immigrants rights group known as the Fishes, former activist turned cynical bureaucrat Theo Faron (Clive Owen) is 
brought to its leader, his estranged American wife Julian Taylor (Julianne Moore), from whom he separated after their son died from 
a flu pandemic in 2008.', 4.75, 3, 5)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bring It On', 'Peyton Reed', '2000-08-25', 'Torrance Shipman (Kirsten Dunst) anxiously dreams about her first day of senior year. 
Her boyfriend, Aaron (Richard Hillman), has left for college, and her cheerleading squad, the Toros, is aiming for a sixth consecutive 
national title. Team captain, "Big Red" (Lindsay Sloane), is graduating and Torrance is elected to take her place. Shortly after her 
election, however, a team member is injured and can no longer compete. Torrance replaces her with Missy Pantone (Eliza Dushku), 
a gymnast who recently transferred to the school with her brother, Cliff (Jesse Bradford). Torrance and Cliff develop a flirtatious 
friendship.', 4.75, 3, 5)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Elephant Man', 'David Lynch', '1980-10-03', 'London Hospital surgeon Frederick Treves discovers John Merrick in a Victorian 
freak show in Londons East End, where he is managed by the brutish Bytes. Merrick is deformed to the point that he must wear a hood 
and cap when in public, and Bytes claims he is an imbecile. Treves is professionally intrigued by Merricks condition and pays Bytes to 
bring him to the Hospital so that he can examine him. There, Treves presents Merrick to his colleagues in a lecture theatre, displaying 
him as a physiological curiosity. Treves draws attention to Merricks most life-threatening deformity, his abnormally large skull, which 
compels him to sleep with his head resting upon his knees, as the weight of his skull would asphyxiate him if he were to ever lie down. 
On Merricks return, Bytes beats him severely enough that a sympathetic apprentice alerts Treves, who returns him to the hospital. 
Bytes accuses Treves of likewise exploiting Merrick for his own ends, leading the surgeon to resolve to do what he can to help the 
unfortunate man.', 3.25, 5, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Fly', 'David Cronenberg', '1986-08-15', 'Seth Brundle (Jeff Goldblum), a brilliant but eccentric scientist, meets Veronica 
Quaife (Geena Davis), a journalist for Particle magazine, at a meet-the-press event held by Bartok Science Industries, the company 
that provides funding for Brundles work. Seth takes Veronica back to the warehouse that serves as both his home and laboratory, and 
shows her a project that will change the world: a set of "Telepods" that allows instantaneous teleportation of an object from one pod 
to another. Veronica eventually agrees to document Seths work. Although the Telepods can transport inanimate objects, they do not 
work properly on living things, as is demonstrated when a live baboon is turned inside-out during an experiment. Seth and Veronica 
begin a romantic relationship. Their first sexual encounter provides inspiration for Seth, who successfully reprograms the Telepod 
computer to cope with living creatures, and teleports a second baboon with no apparent harm.', 3.25, 5, 6) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Frances', 'Graeme Clifford', '1982-12-03', 'Born in Seattle, Washington, Frances Elena Farmer is a rebel from a young age, 
winning a high school award by writing an essay called "God Dies" in 1931. Later that decade, she becomes controversial again when 
she wins (and accepts) an all-expenses-paid trip to the USSR in 1935. Determined to become an actress, Frances is equally determined 
not to play the Hollywood game: she refuses to acquiesce to publicity stunts, and insists upon appearing on screen without makeup. 
Her defiance attracts the attention of Broadway playwright Clifford Odets, who convinces Frances that her future rests with the 
Group Theatre.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Young Frankenstein', 'Mel Brooks', '1974-12-15', 'Dr. Frederick Frankenstein (Gene Wilder) is a physician lecturer at an American 
medical school and engaged to the tightly wound Elizabeth (Madeline Kahn). He becomes exasperated when anyone brings up the 
subject of his grandfather, the infamous mad scientist. To disassociate himself from his legacy, Frederick insists that his surname be 
pronounced "Fronk-en-steen".', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Top Gun', 'Tony Scott', '1986-05-16', 'United States Naval Aviator Lieutenant Pete "Maverick" Mitchell (Tom Cruise) flies the 
F-14A Tomcat off USS Enterprise (CVN-65), with Radar Intercept Officer ("RIO") Lieutenant (Junior Grade) Nick "Goose" Bradshaw 
(Anthony Edwards). At the start of the film, wingman "Cougar" (John Stockwell) and his radar intercept officer "Merlin" (Tim Robbins), 
intercept MiG-28s over the Indian Ocean. During the engagement, one of the MiGs manages to get missile lock on Cougar. While 
Maverick realizes that the MiG "(would) have fired by now", if he really meant to fight, and drives off the MiGs, Cougar is too shaken 
afterward to land, despite being low on fuel. Maverick defies orders and shepherds Cougar back to the carrier, despite also being low 
on fuel. After they land, Cougar retires ("turns in his wings"), stating that he has been holding on "too tight" and has lost "the edge", 
almost orphaning his newborn child, whom he has never seen.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Crimson Tide', 'Tony Scott', '1995-05-12', 'In post-Soviet Russia, military units loyal to Vladimir Radchenko, an ultranationalist, 
have taken control of a nuclear missile installation and are threatening nuclear war if either the American or Russian governments 
attempt to confront him.', 3.25, 5, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Rock', 'Michael Bay', '1996-06-07', 'A group of rogue U.S. Force Recon Marines led by disenchanted Brigadier General Frank 
Hummel (Ed Harris) seize a stockpile of deadly VX gas–armed rockets from a heavily guarded US Navy bunker, reluctantly leaving one 
of their men to die in the process, when a bead of the gas falls and breaks. The next day, Hummel and his men, along with more 
renegade Marines Captains Frye (Gregory Sporleder) and Darrow (Tony Todd) (who have never previously served under Hummel) seize 
control of Alcatraz during a guided tour and take 81 tourists hostage in the prison cells. Hummel threatens to launch the stolen 
rockets against the population of San Francisco if the media is alerted or payment is refused or unless the government pays $100 
million in ransom and reparations to the families of Recon Marines, (using money the U.S. earned via illegal weapons sales) who died 
on illegal, clandestine missions under his command and whose deaths were not honored.', 3.25, 5, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Con Air', 'Simon West', '1997-06-06', 'Former U.S. Army Ranger Cameron Poe is sentenced to a maximum-security federal 
penitentiary for using excessive force and killing a drunk man who had been attempting to assault his pregnant wife, Tricia. Eight 
years later, Poe is paroled on good behavior, and eager to see his daughter Casey whom he has never met. Poe is arranged to be flown 
back home to Alabama on the C-123 Jailbird where he will be released on landing; several other prisoners, including his diabetic 
cellmate and friend Mike "Baby-O" ODell and criminal mastermind Cyrus "The Virus" Grissom, as well as Grissoms right-hand man, 
Nathan Jones, are also being transported to a new Supermax prison. DEA agent Duncan Malloy wishes to bring aboard one of his agents, 
Willie Sims, as a prisoner to coax more information out of drug lord Francisco Cindino before he is incarcerated. Vince Larkin, the U.S. 
Marshal overseeing the transfer, agrees to it, but is unaware that Malloy has armed Sims with a gun.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('National Treasure', 'Jon Turteltaub', '2004-11-19', 'Benjamin Franklin Gates (Nicolas Cage) is a historian and amateur cryptologist, 
and the youngest descendant of a long line of treasure hunters. Though Bens father, Patrick Henry Gates, tries to discourage Ben from 
following in the family line, as he had spent over 20 years looking for the national treasure, attracting ridicule on the family name, 
young Ben is encouraged onward by a clue, "The secret lies with Charlotte", from his grandfather John Adams Gates in 1974, that 
could lead to the fabled national treasure hidden by the Founding Fathers of the United States and Freemasons during the American 
Revolutionary War that was entrusted to his family by Charles Carroll of Carrollton in 1832 before his death to find, and protect the 
family name.', 4.75, 3, 15)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Hope Floats', 'Forest Whitaker', '1998-05-29', 'Birdee Pruitt (Sandra Bullock) is a Chicago housewife who is invited onto a talk 
show under the pretense of getting a free makeover. The makeover she is given is hardly what she has in mind...as she is ambushed 
with the revelation that her husband Bill has been having an affair behind her back with her best friend Connie. Humiliated on 
national television, Birdee and her daughter Bernice (Mae Whitman) move back to Birdees hometown of Smithville, Texas with 
Birdees eccentric mother Ramona (Gena Rowlands) to try to make a fresh start. As Birdee and Bernice leave Chicago, Birdee gives 
Bernice a letter from her father, telling Bernice how much he misses her.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Gun Shy', 'Eric Blakeney', '2000-02-04', 'Charlie Mayeaux (Liam Neeson) is an undercover DEA agent suffering from anxiety and 
gastrointestinal problems after a bust gone wrong. During the aforementioned incident, his partner was killed and he found himself 
served up on a platter of watermelon with a gun shoved in his face just before back-up arrived. Charlie, once known for his ease and 
almost "magical" talent on the job, is finding it very hard to return to work. His requests to be taken off the case or retired are denied 
by his bosses, Lonny Ward (Louis Giambalvo) and Dexter Helvenshaw (Mitch Pileggi) as so much time was put into his cover. Charlie 
works with the dream of one day retiring to Ocean Views, a luxury housing complex with servants and utilities.', 4.75, 3, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Miss Congeniality', 'Donald Petrie', '2000-12-22', 'The film opens at a school where a boy is picking on another boy. We see 
Gracie Hart (Mary Ashleigh Green) as a child who beats up the bully and tries to help the victim (whom she liked), who instead 
criticizes her by saying he disliked her because he did not want a girl to help him. She promptly punches the boy in the nose and sulks 
in the playground.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Murder by Numbers', 'Barbet Schroeder', '2002-04-19', 'Richard Haywood, a wealthy and popular high-schooler, secretly teams 
up with another rich kid in his class, brilliant nerd Justin "Bonaparte" Pendleton. His erudition, especially in forensic matters, allows 
them to plan elaborately perfect murders as a perverse form of entertainment. Meeting in a deserted resort, they drink absinthe, 
smoke, and joke around, but pretend to have an adversarial relationship while at school. Justin, in particular, behaves strangely, 
writing a paper about how crime is freedom and vice versa, and creating a composite photograph of himself and Richard.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Two Weeks Notice', 'Marc Lawrence', '2002-12-18', 'Lucy Kelson (Sandra Bullock) is a liberal lawyer who specializes in 
environmental law in New York City. George Wade (Hugh Grant) is an immature billionaire real estate tycoon who has almost 
everything and knows almost nothing. Lucys hard work and devotion to others contrast sharply with Georges world weary 
recklessness and greed.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Miss Congeniality 2: Armed and Fabulous', 'John Pasquin', '2005-03-24', 'Three weeks after the events of the first film, FBI agent 
Gracie Hart (Sandra Bullock) has become a celebrity after she infiltrated a beauty pageant on her last assignment. Her fame results in 
her cover being blown while she is trying to prevent a bank heist.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('All About Steve', 'Phil Traill', '2009-09-04', 'Mary Horowitz, a crossword puzzle writer for the Sacramento Herald, is socially 
awkward and considers her pet hamster her only true friend.  Her parents decide to set her up on a blind date. Marys expectations 
are low, as she tells her hamster. However, she is extremely surprised when her date turns out to be handsome and charming Steve 
Miller, a cameraman for the television news network CCN. However, her feelings for Steve are not reciprocated. After an attempt at 
an intimate moment fails, in part because of her awkwardness and inability to stop talking about vocabulary, Steve fakes a phone call 
about covering the news out of town. Trying to get Mary out of his truck, he tells her he wishes she could be there.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Nightmare Before Christmas', 'Henry Selick', '1993-10-29', 'Halloween Town is a dream world filled with citizens such as 
deformed monsters, ghosts, ghouls, goblins, vampires, werewolves and witches. Jack Skellington ("The Pumpkin King") leads them in a 
frightful celebration every Halloween, but he has grown tired of the same routine year after year. Wandering in the forest outside the 
town center, he accidentally opens a portal to "Christmas Town". Impressed by the feeling and style of Christmas, Jack presents his 
findings and his (somewhat limited) understanding of the festivities to the Halloween Town residents. They fail to grasp his meaning 
and compare everything he says to their idea of Halloween. He reluctantly decides to play along and announces that they will take 
over Christmas.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cabin Boy', 'Adam Resnick', '1994-01-07', 'Nathaniel Mayweather (Chris Elliott) is a snobbish, self-centered, virginal man. He is 
invited by his father to sail to Hawaii aboard the Queen Catherine. After annoying the driver, he is forced to walk the rest of the way.  
Nathaniel makes a wrong turn into a small fishing village where he meets the imbecilic cabin boy/first mate Kenny (Andy Richter). He 
thinks the ship, The Filthy Whore, is a theme boat. It is not until the next morning that Captain Greybar (Ritch Brinkley) finds 
Nathaniel in his room and explains that the boat will not return to dry land for three months.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('James and the Giant Peach', 'Henry Selick', '1996-04-12', 'In the 1930s, James Henry Trotter is a young boy who lives with his 
parents by the sea in the United Kingdom. On Jamess birthday, they plan to go to New York City and visit the Empire State Building, 
the tallest building in the world. However, his parents are later killed by a ghostly rhinoceros from the sky and finds himself living 
with his two cruel aunts, Spiker and Sponge.', 3.25, 5, 15)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('9', 'Shane Acker', '2009-09-09', 'Prior to the events of film, a scientist is ordered by his dictator to create a machine in the 
apparent name of progress. The Scientist uses his own intellect to create the B.R.A.I.N., a thinking robot. However, the dictator 
quickly seizes it and integrates it into the Fabrication Machine, an armature that can construct an army of war machines to destroy 
the dictators enemies. Lacking a soul, the Fabrication Machine is corrupted and exterminates all organic life using toxic gas. In 
desperation, the Scientist uses alchemy to create nine homunculus-like rag dolls known as Stitchpunks using portions of his own soul 
via a talisman, but dies as a result.', 4.75, 3, 16)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bruce Almighty', 'Tom Shadyac', '2003-05-23', 'Bruce Nolan (Jim Carrey) is a television field reporter for Eyewitness News on 
WKBW-TV in Buffalo, New York but desires to be the news anchorman. When he is passed over for the promotion in favour of his 
co-worker rival, Evan Baxter (Steve Carell), he becomes furious and rages during an interview at Niagara Falls, his resulting actions 
leading to his suspension from the station, followed by a series of misfortunes such as getting assaulted by a gang of thugs for standing 
up for a blind man they are beating up as he later on meets with them again and asks them to apologize for beating him up. Bruce 
complains to God that Hes "the one that should be fired".', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Fun with Dick and Jane', 'Dean Parisot', '2005-12-21', 'In January 2000, Dick Harper (Jim Carrey) has been promoted to VP of 
Communication for his company, Globodyne. Soon after, he is asked to appear on the show Money Life, where host Sam Samuels and 
then independent presidential candidate Ralph Nader dub him and all the companys employees as "perverters of the American dream" 
and claim that Globodyne helps the super rich get even wealthier. As they speak, the companys stock goes into a free-fall and is soon 
worthless, along with all the employees pensions, which are in Globodynes stock. Dick arrives home to find his excited wife Jane (Téa 
Leoni), who informs him that she took his advice and quit her job in order to spend more time with their son Billy.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Blood Simple', 'Joel Coen', '1985-01-18', 'Julian Marty (Dan Hedaya), the owner of a Texas bar, suspects his wife Abby (Frances 
McDormand) is having an affair with one of his bartenders, Ray (John Getz). Marty hires private detective Loren Visser (M. Emmet 
Walsh) to take photos of Ray and Abby in bed at a local motel. The morning after their tryst, Marty makes a menacing phone call to 
them, making it clear he is aware of their relationship.', 3.25, 5, 18)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Raising Arizona', 'Joel Coen', '1987-03-06', 'Criminal Herbert I. "Hi" McDunnough (Nicolas Cage) and policewoman Edwina "Ed" 
(Holly Hunter) meet after she takes the mugshots of the recidivist. With continued visits, Hi learns that Eds fiancé has left her. Hi 
proposes to her after his latest release from prison, and the two get married. They move into a desert mobile home, and Hi gets a job 
in a machine shop. They want to have children, but Ed discovers that she is infertile. Due to His criminal record, they cannot adopt a 
child. The couple learns of the "Arizona Quints," sons of locally famous furniture magnate Nathan Arizona (Trey Wilson); Hi and Ed 
kidnap one of the five babies, whom they believe to be Nathan Junior.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Barton Fink', 'Joel Coen', '1991-08-21', 'Barton Fink (John Turturro) is enjoying the success of his first Broadway play, Bare 
Ruined Choirs. His agent informs him that Capitol Pictures in Hollywood has offered a thousand dollars per week to write movie 
scripts. Barton hesitates, worried that moving to California would separate him from "the common man", his focus as a writer. He 
accepts the offer, however, and checks into the Hotel Earle, a large and unusually deserted building. His room is sparse and draped in 
subdued colors; its only decoration is a small painting of a woman on the beach, arm raised to block the sun.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Fargo', 'Joel Coen', '1996-03-08', 'In the winter of 1987, Minneapolis automobile salesman Jerry Lundegaard (Macy) is in financial 
trouble. Jerry is introduced to criminals Carl Showalter (Buscemi) and Gaear Grimsrud (Stormare) by Native American ex-convict 
Shep Proudfoot (Reevis), a mechanic at his dealership. Jerry travels to Fargo, North Dakota and hires the two men to kidnap his wife 
Jean (Rudrüd) in exchange for a new 1987 Oldsmobile Cutlass Ciera and half of the $80,000 ransom. However, Jerry intends to demand 
a much larger sum from his wealthy father-in-law Wade Gustafson (Presnell) and keep most of the money for himself.', 3.25, 5, 19)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('No Country for Old Men', 'Joel Coen', '2007-11-09', 'West Texas in June 1980 is desolate, wide open country, and Ed Tom Bell 
(Tommy Lee Jones) laments the increasing violence in a region where he, like his father and grandfather before him, has risen to the 
office of sheriff.', 4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Vanilla Sky', 'Cameron Crowe', '2001-12-14', 'David Aames (Tom Cruise) was the wealthy owner of a large publishing firm in New 
York City after the death of his father. From a prison cell, David, in a prosthetic mask, tells his story to psychiatrist Dr. Curtis McCabe 
(Kurt Russell): enjoying the bachelor lifestyle, he is introduced to Sofia Serrano (Penélope Cruz) by his best friend, Brian Shelby (Jason 
Lee), at a party. David and Sofia spend a night together talking, and fall in love. When Davids former girlfriend, Julianna "Julie" 
Gianni (Cameron Diaz), hears of Sofia, she attempts to kill herself and David in a car crash. While Julie dies, David remains alive, but 
his face is horribly disfigured, forcing him to wear a mask to hide the injuries. Unable to come to grips with the mask, he gets drunk 
on a night out at a bar with Sofia, and he is left to wallow in the street.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Narc', 'Joe Carnahan', '2003-01-10', 'Undercover narcotics officer Nick Tellis (Jason Patric) chases a drug dealer through the 
streets of Detroit after Tellis identity has been discovered. After the dealer fatally injects a bystander (whom Tellis was forced to 
leave behind) with drugs, he holds a young child hostage. Tellis manages to shoot and kill the dealer before he can hurt the child. 
However, one of the bullets inadvertently hits the childs pregnant mother, causing her to eventually miscarry.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Others', 'Alejandro Amenábar', '2001-08-10', 'Grace Stewart (Nicole Kidman) is a Catholic mother who lives with her two 
small children in a remote country house in the British Crown Dependency of Jersey, in the immediate aftermath of World War II. The 
children, Anne (Alakina Mann) and Nicholas (James Bentley), have an uncommon disease, xeroderma pigmentosa, characterized by 
photosensitivity, so their lives are structured around a series of complex rules designed to protect them from inadvertent exposure to 
sunlight.', 4.75, 3, 21)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Minority Report', 'Steven Spielberg', '2002-06-21', 'In April 2054, Captain John Anderton (Tom Cruise) is chief of the highly 
controversial Washington, D.C., PreCrime police force. They use future visions generated by three "precogs", mutated humans with 
precognitive abilities, to stop murders; because of this, the city has been murder-free for six years. Though Anderton is a respected 
member of the force, he is addicted to Clarity, an illegal psychoactive drug he began using after the disappearance of his son Sean. 
With the PreCrime force poised to go nationwide, the system is audited by Danny Witwer (Colin Farrell), a member of the United 
States Justice Department. During the audit, the precogs predict that Anderton will murder a man named Leo Crow in 36 hours. 
Believing the incident to be a setup by Witwer, who is aware of Andertons addiction, Anderton attempts to hide the case and quickly 
departs the area before Witwer begins a manhunt for him.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('War of the Worlds', 'Steven Spielberg', '2005-06-29', 'Ray Ferrier (Tom Cruise) is a container crane operator at a New Jersey 
port and is estranged from his children. He is visited by his ex-wife, Mary Ann (Miranda Otto), who drops off the children, Rachel 
(Dakota Fanning) and Robbie (Justin Chatwin), as she is going to visit her parents in Boston. Meanwhile T.V. reports tell of bizarre 
lightning storms which have knocked off power in parts of the Ukraine. Robbie takes Rays car out without his permission, so Ray 
starts searching for him. Outside, Ray notices a strange wall cloud, which starts to send out powerful lightning strikes, disabling all 
electronic devices in the area, including cars, forcing Robbie to come back. Ray heads down the street to investigate. He stops at a 
garage and tells Manny the local mechanic, to replace the solenoid on a dead car.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Last Samurai', 'The Last Samurai', '2003-12-05', 'In 1876, Captain Nathan Algren (Tom Cruise) is traumatized by his massacre 
of Native Americans in the Indian Wars and has become an alcoholic to stave off the memories. Algren is approached by former 
colleague Zebulon Gant (Billy Connolly), who takes him to meet Algrens former Colonel Bagley (Tony Goldwyn), whom Algren despises 
for ordering the massacre. On behalf of businessman Mr. Omura (Masato Harada), Bagley offers Algren a job training conscripts of the 
new Meiji government of Japan to suppress a samurai rebellion that is opposed to Western influence, led by Katsumoto (Ken Watanabe). 
Despite the painful ironies of crushing another tribal rebellion, Algren accepts solely for payment. In Japan he keeps a journal and is 
accompanied by British translator Simon Graham (Timothy Spall), who intends to write an account of Japanese culture, centering on 
the samurai.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Shattered Glass', 'Billy Ray', '2003-10-31', 'Stephen Randall Glass is a reporter/associate editor at The New Republic, a 
well-respected magazine located in Washington, DC., where he is making a name for himself for writing the most colorful stories. 
His editor, Michael Kelly, is revered by his young staff. When David Keene (at the time Chairman of the American Conservative Union) 
questions Glass description of minibars and the drunken antics of Young Republicans at a convention, Kelly backs his reporter when 
Glass admits to one mistake but says the rest is true.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Independence Day', 'Roland Emmerich', '1996-07-02', 'On July 2, an enormous alien ship enters Earths orbit and deploys 36 
smaller saucer-shaped ships, each 15 miles wide, which position themselves over major cities around the globe. David Levinson (Jeff 
Goldblum), a satellite technician for a television network in Manhattan, discovers transmissions hidden in satellite links that he 
realizes the aliens are using to coordinate an attack. David and his father Julius (Judd Hirsch) travel to the White House and warn his 
ex-wife, White House Communications Director Constance Spano (Margaret Colin), and President Thomas J. Whitmore (Bill Pullman) of 
the attack. The President, his daughter, portions of his Cabinet and the Levinsons narrowly escape aboard Air Force One as the alien 
spacecraft destroy Washington D.C., New York City, Los Angeles and other cities around the world.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Godzilla', 'Roland Emmerich', '1998-05-20', 'Following a nuclear incident in French Polynesia, a lizards nest is irradiated by the 
fallout of subsequent radiation. Decades later, a Japanese fishing vessel is suddenly attacked by an enormous sea creature in the 
South Pacific ocean; only one seaman survives. Traumatized, he is questioned by a mysterious Frenchman in a hospital regarding 
what he saw, to which he replies, "Gojira".', 3.25, 5, 24)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Patriot', 'Roland Emmerich', '2000-06-30', 'During the American Revolution in 1776, Benjamin Martin (Mel Gibson), a 
veteran of the French and Indian War and widower with seven children, is called to Charleston to vote in the South Carolina General 
Assembly on a levy supporting the Continental Army. Fearing war against Great Britain, Benjamin abstains. Captain James Wilkins 
(Adam Baldwin) votes against and joins the Loyalists. A supporting vote is nonetheless passed and against his fathers wishes, 
Benjamins eldest son Gabriel (Heath Ledger) joins the Continental Army.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Constantine', 'Francis Lawrence', '2005-02-18', 'John Constantine is an exorcist who lives in Los Angeles. Born with the power to 
see angels and demons on Earth, he committed suicide at age 15 after being unable to cope with his visions. Constantine was revived 
by paramedics but spent two minutes in Hell. He knows that because of his actions his soul is condemned to damnation when he dies, 
and has recently learned that he has developed cancer as a result of his smoking habit.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Shooter', 'Antoine Fuqua', '2007-03-23', 'Bob Lee Swagger (Mark Wahlberg) is a retired U.S. Marine Gunnery Sergeant who served 
as a Force Recon Scout Sniper. He reluctantly leaves a self-imposed exile from his isolated mountain home in the Wind River Range at 
the request of Colonel Isaac Johnson (Danny Glover). Johnson appeals to Swaggers expertise and patriotism to help track down an 
assassin who plans on shooting the president from a great distance with a high-powered rifle. Johnson gives him a list of three cities 
where the President is scheduled to visit so Swagger can determine if an attempt could be made at any of them.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Aviator', 'Martin Scorsese', '2004-12-25', 'In 1914, nine-year-old Howard Hughes is being bathed by his mother. She warns 
him of disease, afraid that he will succumb to a flu outbreak: "You are not safe." By 1927, Hughes (Leonardo DiCaprio) has inherited 
his familys fortune, is living in California. He hires Noah Dietrich (John C. Reilly) to run the Hughes Tool Company.', 4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The 11th Hour', 'Nadia Conners', '2007-08-17', 'With contributions from over 50 politicians, scientists, and environmental 
activists, including former Soviet leader Mikhail Gorbachev, physicist Stephen Hawking, Nobel Prize winner Wangari Maathai, and 
journalist Paul Hawken, the film documents the grave problems facing the planets life systems. Global warming, deforestation, mass 
species extinction, and depletion of the oceans habitats are all addressed. The films premise is that the future of humanity is in 
jeopardy.', 4.75, 3, 22)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Romancing the Stone', 'Robert Zemeckis', '1984-03-30', 'Joan Wilder (Kathleen Turner) is a lonely romance novelist in New York 
City who receives a treasure map mailed to her by her recently-murdered brother-in-law. Her widowed sister, Elaine (Mary Ellen 
Trainor), calls Joan and begs her to come to Cartagena, Colombia because Elaine has been kidnapped by bumbling antiquities 
smugglers Ira (Zack Norman) and Ralph (Danny DeVito), and the map is to be the ransom.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('One Flew Over the Cuckoos Nest', 'Miloš Forman', '1975-11-19', 'In 1963 Oregon, Randle Patrick "Mac" McMurphy (Jack Nicholson), 
a recidivist anti-authoritarian criminal serving a short sentence on a prison farm for statutory rape of a 15-year-old girl, is transferred 
to a mental institution for evaluation. Although he does not show any overt signs of mental illness, he hopes to avoid hard labor and 
serve the rest of his sentence in a more relaxed hospital environment.', 3.25, 5, 12)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Risky Business', 'Paul Brickman', '1983-08-05', 'Joel Goodson (Tom Cruise) is a high school student who lives with his wealthy 
parents in the North Shore area of suburban Chicago. His father wants him to attend Princeton University, so Joels mother tells him 
to tell the interviewer, Bill Rutherford, about his participation in Future Enterprisers, an extracurricular activity in which students 
work in teams to create small businesses.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Beetlejuice', 'Tim Burton', '1988-03-30', 'Barbara and Adam Maitland decide to spend their vacation decorating their idyllic New 
England country home in fictional Winter River, Connecticut. While the young couple are driving back from town, Barbara swerves to 
avoid a dog wandering the roadway and crashes through a covered bridge, plunging into the river below. They return home and, 
based on such subtle clues as their lack of reflection in the mirror and their discovery of a Handbook for the Recently Deceased, begin 
to suspect they might be dead. Adam attempts to leave the house to retrace his steps but finds himself in a strange, otherworldly 
dimension referred to as "Saturn", covered in sand and populated by enormous sandworms.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Hamlet 2', 'Andrew Fleming', '2008-08-22', 'Dana Marschz (Steve Coogan) is a recovering alcoholic and failed actor who has 
become a high school drama teacher in Tucson, Arizona, "where dreams go to die". Despite considering himself an inspirational figure, 
he only has two enthusiastic students, Rand (Skylar Astin) and Epiphany (Phoebe Strole), and a history of producing poorly-received 
school plays that are essentially stage adaptations of popular Hollywood films (his latest being Erin Brockovich). When the new term 
begins, a new intake of students are forced to transfer into his class as it is the only remaining arts elective available due to budget 
cutbacks; they are mostly unenthusiastic and unconvinced by Dana’s pretentions, and Dana comes into conflict with Octavio (Joseph 
Julian Soria), one of the new students.', 4.75, 3, 16)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Michael', 'Nora Ephron', '1996-12-25', 'Vartan Malt (Bob Hoskins) is the editor of a tabloid called the National Mirror that 
specializes in unlikely stories about celebrities and frankly unbelievable tales about ordinary folkspersons. When Malt gets word that a 
woman is supposedly harboring an angel in a small town in Iowa, he figures that this might be up the Mirrors alley, so he sends out 
three people to get the story – Frank Quinlan (William Hurt), a reporter whose career has hit the skids; Huey Driscoll (Robert Pastorelli), 
a photographer on the verge of losing his job (even though he owns the Mirrors mascot Sparky the Wonder Dog); and Dorothy Winters 
(Andie MacDowell), a self-styled "angel expert" (actually a dog trainer hired by Malt to eventually replace Driscoll).', 3.25, 5, 7)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Youve Got Mail', 'Nora Ephron', '1998-12-18', 'Kathleen Kelly (Meg Ryan) is involved with Frank Navasky (Greg Kinnear), a 
leftist postmodernist newspaper writer for the New York Observer whos always in search of an opportunity to root for the underdog. 
While Frank is devoted to his typewriter, Kathleen prefers her laptop and logging into her AOL e-mail account. There, using the screen 
name Shopgirl, she reads an e-mail from "NY152", the screen name of Joe Fox (Tom Hanks). In her reading of the e-mail, she reveals 
the boundaries of the online relationship; no specifics, including no names, career or class information, or family connections. Joe 
belongs to the Fox family which runs Fox Books — a chain of "mega" bookstores similar to Borders or Barnes & Noble.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bewitched', 'Nora Ephron', '2005-06-24', 'Jack Wyatt (Will Ferrell) is a narcissistic actor who is approached to play the role of 
Darrin in a remake of the classic sitcom Bewitched but insists that an unknown play Samantha.  Isabel Bigelow (Nicole Kidman) is an 
actual witch who decides she wants to be normal and moves to Los Angeles to start a new life and becomes friends with her neighbor 
Maria (Kristin Chenoweth). She goes to a bookstore to learn how to get a job after seeing an advertisement of Ed McMahon on TV.', 
4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Love Story', 'Arthur Hiller', '1970-12-16', 'The film tells of Oliver Barrett IV, who comes from a family of wealthy and 
well-respected Harvard University graduates. At Radcliffe library, the Harvard student meets and falls in love with Jennifer Cavalleri, 
a working-class, quick-witted Radcliffe College student. Upon graduation from college, the two decide to marry against the wishes of 
Olivers father, who thereupon severs ties with his son.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Godfather', 'Francis Ford Coppola', '1972-03-15', 'On the day of his only daughters wedding, Vito Corleone hears requests in 
his role as the Godfather, the Don of a New York crime family. Vitos youngest son, Michael, in Marine Corps khakis, introduces his 
girlfriend, Kay Adams, to his family at the sprawling reception. Vitos godson Johnny Fontane, a popular singer, pleads for help in 
securing a coveted movie role, so Vito dispatches his consigliere, Tom Hagen, to the abrasive studio head, Jack Woltz, to secure the 
casting. Woltz is unmoved until the morning he wakes up in bed with the severed head of his prized stallion.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Chinatown', 'Roman Polanski', '1974-06-20', 'A woman identifying herself as Evelyn Mulwray (Ladd) hires private investigator 
J.J. "Jake" Gittes (Nicholson) to perform matrimonial surveillance on her husband Hollis I. Mulwray (Zwerling), the chief engineer for 
the Los Angeles Department of Water and Power. Gittes tails him, hears him publicly oppose the creation of a new reservoir, and 
shoots photographs of him with a young woman (Palmer) that hit the front page of the following days paper. Upon his return to his 
office he is confronted by a beautiful woman who, after establishing that the two of them have never met, irately informs him that 
she is in fact Evelyn Mulwray (Dunaway) and he can expect a lawsuit.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Saint', 'Phillip Noyce', '1997-04-04', 'At the Saint Ignatius Orphanage, a rebellious boy named John Rossi refers to himself 
as "Simon Templar" and leads a group of fellow orphans as they attempt to run away to escape their harsh treatment. When Simon is 
caught by the head priest, he witnesses the tragic death of a girl he had taken a liking to when she accidentally falls from a balcony.', 
3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Alexander', 'Oliver Stone', '2004-11-24', 'The film is based on the life of Alexander the Great, King of Macedon, who conquered 
Asia Minor, Egypt, Persia and part of Ancient India. Shown are some of the key moments of Alexanders youth, his invasion of the 
mighty Persian Empire and his death. It also outlines his early life, including his difficult relationship with his father Philip II of 
Macedon, his strained feeling towards his mother Olympias, the unification of the Greek city-states and the two Greek Kingdoms 
(Macedon and Epirus) under the Hellenic League,[3] and the conquest of the Persian Empire in 331 BC. It also details his plans to 
reform his empire and the attempts he made to reach the end of the then known world.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Terminator Salvation', 'Joseph McGinty Nichol', '2009-05-21', 'In 2003, Doctor Serena Kogan (Helena Bonham Carter) of 
Cyberdyne Systems convinces death row inmate Marcus Wright (Sam Worthington) to sign his body over for medical research following 
his execution by lethal injection. One year later the Skynet system is activated, perceives humans as a threat to its own existence, 
and eradicates much of humanity in the event known as "Judgment Day" (as depicted in Terminator 3: Rise of the Machines).', 
4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('I Know What You Did Last Summer', 'Jim Gillespie', '1997-10-17', 'Four friends, Helen Shivers (Sarah Michelle Gellar), Julie 
James (Jennifer Love Hewitt), Barry Cox (Ryan Phillippe), and Ray Bronson (Freddie Prinze Jr.) go out of town to celebrate Helens 
winning the Miss Croaker pageant. Returning in Barrys new car, they hit and apparently kill a man, who is unknown to them. They 
dump the corpse in the ocean and agree to never discuss again what had happened.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Score', 'Frank Oz', '2001-07-13', 'After nearly being caught on a routine burglary, master safe-cracker Nick Wells (Robert De 
Niro) decides the time has finally come to retire. Nicks flight attendant girlfriend, Diane (Angela Bassett), encourages this decision, 
promising to fully commit to their relationship if he does indeed go straight. Nick, however, is lured into taking one final score by his 
fence Max (Marlon Brando) The job, worth a $4 million pay off to Nick, is to steal a valuable French sceptre, which was being smuggled 
illegally into the United States through Canada but was accidentally discovered and kept at the Montréal Customs House.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Sleepy Hollow', 'Tim Burton', '1999-11-19', 'In 1799, New York City, Ichabod Crane is a 24-year-old police officer. He is dispatched 
by his superiors to the Westchester County hamlet of Sleepy Hollow, New York, to investigate a series of brutal slayings in which the 
victims have been found decapitated: Peter Van Garrett, wealthy farmer and landowner; his son Dirk; and the widow Emily Winship, 
who secretly wed Van Garrett and was pregnant before being murdered. A pioneer of new, unproven forensic techniques such as 
finger-printing and autopsies, Crane arrives in Sleepy Hollow armed with his bag of scientific tools only to be informed by the towns 
elders that the murderer is not of flesh and blood, rather a headless undead Hessian mercenary from the American Revolutionary War 
who rides at night on a massive black steed in search of his missing head.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('I Still Know What You Did Last Summer', 'Danny Cannon', '1998-11-13', 'Julie James is getting over the events of the previous 
film, which nearly claimed her life. She hasnt been doing well in school and is continuously having nightmares involving Ben Willis 
(Muse Watson) still haunting her. Approaching the 4th July weekend, Ray (Freddie Prinze, Jr.) surprises her at her dorm. He invites 
her back up to Southport for the Croaker queen pageant. She objects and tells him she has not healed enough to go back. He tells her 
she needs some space away from Southport and him and leaves in a rush. After getting inside,she sits on her bed and looks at a picture 
of her deceased best friend Helen (Sarah Michelle Gellar), who died the previous summer at the hands of the fisherman.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard with a Vengeance', 'John McTiernan', '1995-05-19', 'In New York City, a bomb detonates destroying the Bonwit Teller 
department store. A man calling himself "Simon" phones Major Case Unit Inspector Walter Cobb of the New York City Police 
Department, claiming responsibility for the bomb. He demands that suspended police officer Lt. John McClane be dropped in Harlem 
wearing a sandwich board that says "I hate Niggers". Harlem shop owner Zeus Carver spots McClane and tries to get him off the street 
before he is killed, but a gang of black youths attack the pair, who barely escape. Returning to the station, they learn that Simon is 
believed to have stolen several thousand gallons of an explosive compound. Simon calls again demanding McClane and Carver put 
themselves through a series of "games" to prevent more explosions.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Terminator 3: Rise of the Machines', 'Jonathan Mostow', '2003-07-02', 'For nine years, John Connor (Nick Stahl) has been living 
off-the-grid in Los Angeles. Although Judgment Day did not occur on August 29, 1997, John does not believe that the prophesied war 
between humans and Skynet has been averted. Unable to locate John, Skynet sends a new model of Terminator, the T-X (Kristanna 
Loken), back in time to July 24, 2004 to kill his future lieutenants in the human Resistance. A more advanced model than previous 
Terminators, the T-X has an endoskeleton with built-in weaponry, a liquid metal exterior similar to the T-1000, and the ability to 
control other machines. The Resistance sends a reprogrammed T-850 model 101 Terminator (Arnold Schwarzenegger) back in time to 
protect the T-Xs targets, including Kate Brewster (Claire Danes) and John.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Amityville Horror', 'Andrew Douglas', '2005-04-15', 'On November 13, 1974, at 3:15am, Ronald DeFeo, Jr. shot and killed his 
family at their home, 112 Ocean Avenue in Amityville, New York. He killed five members of his family in their beds, but his youngest 
sister, Jodie, had been killed in her bedroom closet. He claimed that he was persuaded to kill them by voices he had heard in the 
house.', 4.75, 3, 21)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Runaway Bride', 'Garry Marshall', '1999-07-30', 'Maggie Carpenter (Julia Roberts) is a spirited and attractive young woman who 
has had a number of unsuccessful relationships. Maggie, nervous of being married, has left a trail of fiances. It seems, shes left three 
men waiting for her at the altar on their wedding day (all of which are caught on tape), receiving tabloid fame and the dubious 
nickname "The Runaway Bride".', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Jumanji', 'Joe Johnston', '1995-12-15', 'In 1869, two boys bury a chest in a forest near Keene, New Hampshire. A century later, 
12-year-old Alan Parrish flees from a gang of bullies to a shoe factory owned by his father, Sam, where he meets his friend Carl Bentley, 
one of Sams employees. When Alan accidentally damages a machine with a prototype sneaker Carl hopes to present, Carl takes the 
blame and loses his job. Outside the factory, after the bullies beat Alan up and steal his bicycle, Alan follows the sound of tribal 
drumbeats to a construction site and finds the chest, containing a board game called Jumanji.', 3.25, 5, 24)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Revenge of the Nerds', 'Jeff Kanew', '1984-07-20', 'Best friends and nerds Lewis Skolnick (Robert Carradine) and Gilbert Lowe 
(Anthony Edwards) enroll in Adams College to study computer science. The Alpha Betas, a fraternity to which many members of the 
schools football team belong, carelessly burn down their own house and seize the freshmen dorm for themselves. The college allows 
the displaced freshmen, living in the gymnasium, to join fraternities or move to other housing. Lewis, Gilbert, and other outcasts who 
cannot join a fraternity renovate a dilapidated home to serve as their own fraternity house.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Easy Rider', 'Dennis Hopper', '1969-07-14', 'The protagonists are two freewheeling hippies: Wyatt (Fonda), nicknamed "Captain 
America", and Billy (Hopper). Fonda and Hopper said that these characters names refer to Wyatt Earp and Billy the Kid.[4] Wyatt 
dresses in American flag-adorned leather (with an Office of the Secretary of Defense Identification Badge affixed to it), while Billy 
dresses in Native American-style buckskin pants and shirts and a bushman hat. The former is appreciative of help and of others, while 
the latter is often hostile and leery of outsiders.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Braveheart', 'Mel Gibson', '1995-05-24', 'In 1280, King Edward "Longshanks" (Patrick McGoohan) invades and conqueres Scotland 
following the death of Scotlands King Alexander III who left no heir to the throne. Young William Wallace witnesses the treachery of 
Longshanks, survives the death of his father and brother, and is taken abroad to Rome by his Uncle Argyle (Brian Cox) where he is 
educated.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Passion of the Christ', 'Mel Gibson', '2004-02-25', 'The film opens in Gethsemane as Jesus prays and is tempted by Satan, 
while his apostles, Peter, James and John sleep. After receiving thirty pieces of silver, one of Jesus other apostles, Judas, approaches 
with the temple guards and betrays Jesus with a kiss on the cheek. As the guards move in to arrest Jesus, Peter cuts off the ear of 
Malchus, but Jesus heals the ear. As the apostles flee, the temple guards arrest Jesus and beat him during the journey to the 
Sanhedrin. John tells Mary and Mary Magdalene of the arrest while Peter follows Jesus at a distance. Caiaphas holds trial over the 
objection of some of the other priests, who are expelled from the court.', 4.75, 3, 8)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Finding Neverland', 'Marc Forster', '2004-11-12', 'The story focuses on Scottish writer J. M. Barrie, his platonic relationship with 
Sylvia Llewelyn Davies, and his close friendship with her sons, who inspire the classic play Peter Pan, or The Boy Who Never Grew Up.', 
4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Bourne Identity', 'Doug Liman', '2002-06-14', 'In the Mediterranean Sea near Marseille, Italian fishermen rescue an 
unconscious man floating adrift with two gunshot wounds in his back. The boats medic finds a tiny laser projector surgically implanted 
under the unknown mans skin at the level of the hip. When activated, the laser projector displays the number of a safe deposit box in 
Zürich. The man wakes up and discovers he is suffering from extreme memory loss. Over the next few days on the ship, the man finds 
he is fluent in several languages and has unusual skills, but cannot remember anything about himself or why he was in the sea. When 
the ship docks, he sets off to investigate the safe deposit box.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Cider House Rules', 'Lasse Hallström', '1999-12-17', 'Homer Wells (Tobey Maguire), an orphan, is the films protagonist. He 
grew up in an orphanage directed by Dr. Wilbur Larch (Michael Caine) after being returned twice by foster parents. His first foster 
parents thought he was too quiet and the second parents beat him. Dr. Larch is addicted to ether and is also secretly an abortionist. 
Larch trains Homer in obstetrics and abortions as an apprentice, despite Homer never even having attended high school.', 3.25, 5, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Field of Dreams', 'Phil Alden Robinson', '1989-04-21', 'While walking in his cornfield, novice farmer Ray Kinsella hears a voice 
that whispers, "If you build it, he will come", and sees a baseball diamond. His wife, Annie, is skeptical, but she allows him to plow 
under his corn to build the field.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Waterworld', 'Kevin Reynolds', '1995-07-28', 'In the future (year 2500), the polar ice caps have melted due to the global warming, 
and the sea level has risen hundreds of meters, covering every continent and turning Earth into a water planet. Human population 
has been scattered across the ocean in individual, isolated communities consisting of artificial islands and mostly decrepit sea vessels. 
It was so long since the events that the humans eventually forgot that there were continents in the first place and that there is a 
place on Earth called "the Dryland", a mythical place.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard', 'John McTiernan', '1988-07-15', 'New York City Police Department detective John McClane arrives in Los Angeles to 
reconcile with his estranged wife, Holly. Limo driver Argyle drives McClane to the Nakatomi Plaza building to meet Holly at a company 
Christmas party. While McClane changes clothes, the party is disrupted by the arrival of German terrorist Hans Gruber and his heavily 
armed group: Karl, Franco, Tony, Theo, Alexander, Marco, Kristoff, Eddie, Uli, Heinrich, Fritz and James. The group seizes the 
skyscraper and secure those inside as hostages, except for McClane, who manages to slip away, armed with only his service sidearm, a 
Beretta 92F pistol.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard 2', 'Renny Harlin', '1990-07-04', 'On Christmas Eve, two years after the Nakatomi Tower Incident, John McClane is 
waiting at Washington Dulles International Airport for his wife Holly to arrive from Los Angeles, California. Reporter Richard Thornburg, 
who exposed Hollys identity to Hans Gruber in Die Hard, is assigned a seat across the aisle from her. While in the airport bar, McClane 
spots two men in army fatigues carrying a package; one of the men has a gun. Suspicious, he follows them into the baggage area. After 
a shootout, he kills one of the men while the other escapes. Learning the dead man is a mercenary thought to have been killed in 
action, McClane believes hes stumbled onto a nefarious plot. He relates his suspicions to airport police Captain Carmine Lorenzo, but 
Lorenzo refuses to listen and has McClane thrown out of his office.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Splash', 'Ron Howard', '1984-03-09', 'As an eight year-old boy, Allen Bauer (David Kreps) is vacationing with his family near Cape 
Cod. While taking a sight-seeing tour on a ferry, he gazes into the ocean and sees something below the surface that fascinates him. 
Allen jumps into the water, even though he cannot swim. He grasps the hands of a girl who is inexplicably under the water with him 
and an instant connection forms between the two. Allen is quickly pulled to the surface by the deck hands and the two are separated, 
though apparently no one else sees the girl. After the ferry moves off, Allen continues to look back at the girl in the water, who cries 
at their separation.', 3.25, 5, 25)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Parenthood', 'Ron Howard', '1989-08-02', 'Gil Buckman (Martin), a neurotic sales executive, is trying to balance his family and 
his career in suburban St. Louis. When he finds out that his eldest son, Kevin, has emotional problems and needs therapy, and that his 
two younger children, daughter Taylor and youngest son Justin, both have issues as well, he begins to blame himself and questions his 
abilities as a father. When his wife, Karen (Steenburgen), becomes pregnant with their fourth child, he is unsure he can handle it.', 
3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Apollo 13', 'Ron Howard', '1995-06-30', 'On July 20, 1969, veteran astronaut Jim Lovell (Tom Hanks) hosts a party for other 
astronauts and their families, who watch on television as their colleague Neil Armstrong takes his first steps on the Moon during the 
Apollo 11 mission. Lovell, who orbited the Moon on Apollo 8, tells his wife Marilyn (Kathleen Quinlan) that he intends to return, to 
walk on its surface.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Dr. Seuss How the Grinch Stole Christmas', 'Ron Howard', '2000-11-17', 'In the microscopic city of Whoville, everyone celebrates 
Christmas with much happiness and joy, with the exception of the cynical and misanthropic Grinch (Jim Carrey), who despises 
Christmas and the Whos with great wrath and occasionally pulls dangerous and harmful practical jokes on them. As a result, no one 
likes or cares for him.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('A Beautiful Mind', 'Ron Howard', '2001-12-21', 'In 1947, John Nash (Russell Crowe) arrives at Princeton University. He is co-recipient, 
with Martin Hansen (Josh Lucas), of the prestigious Carnegie Scholarship for mathematics. At a reception he meets a group of other 
promising math and science graduate students, Richard Sol (Adam Goldberg), Ainsley (Jason Gray-Stanford), and Bender (Anthony Rapp). 
He also meets his roommate Charles Herman (Paul Bettany), a literature student, and an unlikely friendship begins.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Da Vinci Code', 'Ron Howard', '2006-05-19', 'In Paris, Jacques Saunière is pursued through the Louvres Grand Gallery by 
albino monk Silas (Paul Bettany), demanding the Priorys clef de voûte or "keystone." Saunière confesses the keystone is kept in the 
sacristy of Church of Saint-Sulpice "beneath the Rose" before Silas shoots him. At the American University of Paris, Robert Langdon, a 
symbologist who is a guest lecturer on symbols and the sacred feminine, is summoned to the Louvre to view the crime scene. He 
discovers the dying Saunière has created an intricate display using black light ink and his own body and blood. Captain Bezu Fache 
(Jean Reno) asks him for his interpretation of the puzzling scene.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Simpsons Movie', 'David Silverman', '2007-07-27', 'While performing on Lake Springfield, rock band Green Day are killed 
when pollution in the lake dissolves their barge, following an audience revolt after frontman Billie Joe Armstrong proposes an 
environmental discussion. At a memorial service, Grampa has a prophetic vision in which he predicts the impending doom of the town, 
but only Marge takes it seriously. Then Homer dares Bart to skate naked and he does so. Lisa and an Irish boy named Colin, with whom 
she has fallen in love, hold a meeting where they convince the town to clean up the lake.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Crash', 'Paul Haggis', '2005-05-06', 'Los Angeles detectives Graham Waters (Don Cheadle) and his partner Ria (Jennifer Esposito) 
approach a crime scene investigation. Waters exits the car to check out the scene. One day prior, Farhad (Shaun Toub), a Persian 
shop owner, and his daughter, Dorri (Bahar Soomekh), argue with each other in front of a gun store owner as Farhad tries to buy a 
revolver. The shop keeper grows impatient and orders an infuriated Farhad outside. Dorri defiantly finishes the gun purchase, which 
she had opposed. The purchase entitles the buyer to one box of ammunition. She selects a red box.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Million Dollar Baby', 'Clint Eastwood', '2004-12-15', 'Margaret "Maggie" Fitzgerald, a waitress from a Missouri town in the Ozarks, 
shows up in the Hit Pit, a run-down Los Angeles gym which is owned and operated by Frankie Dunn, a brilliant but only marginally 
successful boxing trainer. Maggie asks Dunn to train her, but he angrily responds that he "doesnt train girls."', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Letters from Iwo Jima', 'Clint Eastwood', '2006-12-20', 'In 2005, Japanese archaeologists explore tunnels on Iwo Jima, where they 
find something buried in the soil.  The film flashes back to Iwo Jima in 1944. Private First Class Saigo is grudgingly digging trenches on 
the beach. A teenage baker, Saigo has been conscripted into the Imperial Japanese Army despite his youth and his wifes pregnancy. 
Saigo complains to his friend Private Kashiwara that they should let the Americans have Iwo Jima. Overhearing them, an enraged 
Captain Tanida starts brutally beating them for "conspiring with unpatriotic words." At the same time, General Tadamichi Kuribayashi 
arrives to take command of the garrison and immediately begins an inspection of the island defenses.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cast Away', 'Robert Zemeckis', '2000-12-07', 'In 1995, Chuck Noland (Tom Hanks) is a time-obsessed systems analyst, who travels 
worldwide resolving productivity problems at FedEx depots. He is in a long-term relationship with Kelly Frears (Helen Hunt), whom he 
lives with in Memphis, Tennessee. Although the couple wants to get married, Chucks busy schedule interferes with their relationship. 
A Christmas with relatives is interrupted by Chuck being summoned to resolve a problem in Malaysia.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cloverfield', 'J. J. Abrams', '2008-01-18', 'The film is presented as found footage from a personal video 
camera recovered by the United States Department of Defense. A disclaimer text states that the footage is of a case 
designated "Cloverfield" and was found in the area "formerly known as Central Park". The video consists chiefly of 
segments taped the night of Friday, May 22, 2009. The newer segments were taped over older video that is shown 
occasionally.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Mission: Impossible III', 'J. J. Abrams', '2006-05-05', 'Ethan Hunt (Tom Cruise) has retired from active field work for the 
Impossible Missions Force (IMF) and instead trains new recruits while settling down with his fiancée Julia Meade (Michelle Monaghan), 
a nurse at a local hospital who is unaware of Ethans past. Ethan is approached by fellow IMF agent John Musgrave (Billy Crudup) 
about a mission for him: rescue one of Ethans protégés, Lindsey Farris (Keri Russell), who was captured while investigating arms 
dealer Owen Davian (Philip Seymour Hoffman). Musgrave has already prepared a team for Ethan, consisting of Declan Gormley 
(Jonathan Rhys Meyers), Zhen Lei (Maggie Q), and his old partner Luther Stickell (Ving Rhames), in Berlin, Germany.', 4.75, 3, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Star Trek', 'J. J. Abrams', '2009-05-08', 'In 2233, the Federation starship USS Kelvin is investigating a "lightning storm" in space. 
A Romulan ship, the Narada, emerges from the storm and attacks the Kelvin. Naradas first officer, Ayel, demands that the Kelvins 
Captain Robau come aboard to discuss a cease fire. Once aboard, Robau is questioned about an "Ambassador Spock", who he states 
that he is "not familiar with", as well as the current stardate, after which the Naradas commander, Nero, flies into a rage and kills 
him, before continuing to attack the Kelvin. The Kelvins first officer, Lieutenant Commander George Kirk, orders the ships personnel 
evacuated via shuttlecraft, including his pregnant wife, Winona. Kirk steers the Kelvin on a collision course at the cost of his own life, 
while Winona gives birth to their son, James Tiberius Kirk.', 4.75, 3, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Halloween', 'John Carpenter', '1978-10-25', 'On Halloween night, 1963, in fictional Haddonfield, Illinois, 6-year-old Michael 
Myers (Will Sandin) murders his older teenage sister Judith (Sandy Johnson), stabbing her repeatedly with a butcher knife, after she 
had sex with her boyfriend. Fifteen years later, on October 30, 1978, Michael escapes the hospital in Smiths Grove, Illinois where he 
had been committed since the murder, stealing the car that was to take him to a court hearing.', 3.25, 5, 2)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Cable Guy', 'Ben Stiller', '1996-06-14', 'After a failed marriage proposal to his girlfriend Robin Harris (Leslie Mann), Steven 
M. Kovacs (Matthew Broderick) moves into his own apartment after they agree to spend some time apart. Enthusiastic cable guy 
Ernie "Chip" Douglas (Jim Carrey), an eccentric man with a lisp, installs his cable. Taking advice from his friend Rick (Jack Black), 
Steven bribes Chip to give him free movie channels, to which Chip agrees. Before he leaves, Chip gets Steven to hang out with him 
the next day and makes him one of his "preferred customers".', 3.25, 5, 3)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Anchorman: The Legend of Ron Burgundy', 'Adam McKay', '2004-07-09', 'In 1975, Ron Burgundy (Will Ferrell) is the famous and 
successful anchorman for San Diegos KVWN-TV Channel 4 Evening News. He works alongside his friends on the news team: 
fashion-oriented lead field reporter Brian Fantana (Paul Rudd), sportscaster Champion "Champ" Kind (David Koechner), and a "legally 
retarded" chief meteorologist Brick Tamland (Steve Carell). The team is notified by their boss, Ed Harken (Fred Willard), that their 
station has maintained its long-held status as the highest-rated news program in San Diego, leading them to throw a wild party. Ron 
sees an attractive blond woman and immediately tries to hit on her. After an awkward, failed pick-up attempt, the woman leaves.', 4.75, 3, 4) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The 40-Year-Old Virgin', 'Judd Apatow', '2005-08-19', 'Andy Stitzer (Steve Carell) is the eponymous 40-year-old virgin; he is 
involuntarily celibate. He lives alone, and is somewhat childlike; he collects action figures, plays video games, and his social life 
seems to consist of watching Survivor with his elderly neighbors. He works in the stockroom at an electronics store called SmartTech. 
When a friend drops out of a poker game, Andys co-workers David (Paul Rudd), Cal (Seth Rogen), and Jay (Romany Malco) reluctantly 
invite Andy to join them. At the game, when conversation turns to past sexual exploits, Andy desperately makes up a story, but when 
he compares the feel of a womans breast to a "bag of sand", he is forced to admit his virginity. Feeling sorry for him (but also 
generally mocking him), the group resolves to help Andy lose his virginity.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Knocked Up', 'Judd Apatow', '2007-06-01', 'Ben Stone (Seth Rogen) is laid-back and sardonic. He lives off funds received in 
compensation for an injury and sporadically works on a celebrity porn website with his roommates, in between smoking marijuana 
or going off with them at theme parks such as Knotts Berry Farm. Alison Scott (Katherine Heigl) is a career-minded woman who has 
just been given an on-air role with E! and is living in the pool house with her sister Debbies (Leslie Mann) family. While celebrating 
her promotion, Alison meets Ben at a local nightclub. After a night of drinking, they end up having sex. Due to a misunderstanding, 
they do not use protection: Alison uses the phrase "Just do it already" to encourage Ben to put the condom on, but he misinterprets 
this to mean to dispense with using one. The following morning, they quickly learn over breakfast that they have little in common 
and go their separate ways, which leaves Ben visibly upset.', 4.75, 3, 5) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Superbad', 'Greg Mottola', '2007-08-17', 'Seth (Jonah Hill) and Evan (Michael Cera) are two high school seniors who lament their 
virginity and poor social standing. Best friends since childhood, the two are about to go off to different colleges, as Seth did not get 
accepted into Dartmouth. After Seth is paired with Jules (Emma Stone) during Home-Ec class, she invites him to a party at her house 
later that night. Later, Fogell (Christopher Mintz-Plasse) comes up to the two and reveals his plans to obtain a fake ID during lunch. 
Seth uses this to his advantage and promises to bring alcohol to Jules party.', 4.75, 3, 3) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Donnie Darko', 'Richard Kelly', '2001-10-26', 'On October 2, 1988, Donnie Darko (Jake Gyllenhaal), a troubled teenager living in 
Middlesex, Virginia, is awakened and led outside by a figure in a monstrous rabbit costume, who introduces himself as "Frank" and 
tells him the world will end in 28 days, 6 hours, 42 minutes and 12 seconds. At dawn, Donnie awakens on a golf course and returns 
home to find a jet engine has crashed into his bedroom. His older sister, Elizabeth (Maggie Gyllenhaal), informs him the FAA 
investigators dont know where it came from.', 4.75, 3, 8)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Never Been Kissed', 'Raja Gosnell', '1999-04-09', 'Josie Geller (Drew Barrymore) is a copy editor for the Chicago Sun-Times who 
has never had a real relationship. One day during a staff meeting, the tyrannical editor-in-chief, Rigfort (Garry Marshall) assigns her 
to report undercover at a high school to help parents become more aware of their childrens lives.  Josie tells her brother Rob (David 
Arquette) about the assignment, and he reminds her that during high school she was a misfit labelled "Josie Grossie", a nickname 
which continues to haunt her.', 3.25, 5, 6)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Duplex', 'Danny DeVito', '2003-09-26', 'Alex Rose and Nancy Kendricks are a young, professional, New York couple in search of 
their dream home. When they finally find the perfect Brooklyn brownstone they are giddy with anticipation. The duplex is a dream 
come true, complete with multiple fireplaces, except for one thing: Mrs. Connelly, the old lady who lives on the rent-controlled top 
floor. Assuming she is elderly and ill, they take the apartment.', 4.75, 3, 9)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Music and Lyrics', 'Marc Lawrence', '2007-02-14', 'At the beginning of the film, Alex is a washed-up former pop star who is 
attempting to revive his career by hitching his career to the rising star of Cora Corman, a young megastar who has asked him to write 
a song titled "Way Back Into Love." During an unsuccessful attempt to come up with words for the song, he discovers that the woman 
who waters his plants, Sophie Fisher (Drew Barrymore), has a gift for writing lyrics. Sophie, a former creative writing student reeling 
from a disastrous romance with her former English professor Sloan Cates (Campbell Scott), initially refuses. Alex cajoles her into 
helping him by using a few quickly-chosen phrases she has given him as the basis for a song. Over the next few days, they grow closer 
while writing the words and music together, much to the delight of Sophies older sister Rhonda (Kristen Johnston), a huge fan of 
Alexs.', 4.75, 3, 10) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Charlies Angels', 'Joseph McGinty Nichol', '2000-11-03', 'Natalie Cook (Cameron Diaz), Dylan Sanders (Drew Barrymore) and 
Alex Munday (Lucy Liu) are the "Angels," three talented, tough, attractive women who work as private investigators for an unseen 
millionaire named Charlie (voiced by Forsythe). Charlie uses a speaker in his offices to communicate with the Angels, and his assistant 
Bosley (Bill Murray) works with them directly when needed.', 4.75, 3, 3)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Pulp Fiction', 'Quentin Tarantino', '1994-10-14', 'As Jules and Vincent eat breakfast in a coffee shop the discussion returns to 
Juless decision to retire. In a brief cutaway, we see "Pumpkin" and "Honey Bunny" shortly before they initiate the hold-up from the 
movies first scene. While Vincent is in the bathroom, the hold-up commences. "Pumpkin" demands all of the patrons valuables, 
including Juless mysterious case. Jules surprises "Pumpkin" (whom he calls "Ringo"), holding him at gunpoint. "Honey Bunny" (whose 
name turns out to be Yolanda), hysterical, trains her gun on Jules. Vincent emerges from the restroom with his gun trained on her, 
creating a Mexican standoff. Reprising his pseudo-biblical passage, Jules expresses his ambivalence about his life of crime.', 3.25, 5, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Kill Bill: Volume 1', 'Quentin Tarantino', '2003-10-03', '"The Bride", a former member of an assassination team who seeks 
revenge on her ex-colleagues who massacred members of her wedding party and tried to kill her. During the first movie she succeeds 
in killing two of the five members.', 4.75, 3, 9) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Kill Bill: Volume 2', 'Quentin Tarantino', '2004-04-16', '"The Bride", a former member of an assassination team who seeks 
revenge on her ex-colleagues who massacred members of her wedding party and tried to kill her. The film is often noted for its stylish 
direction and its homages to film genres such as Hong Kong martial arts films, Japanese chanbara films, Italian spaghetti westerns, 
girls with guns, and rape and revenge.', 4.75, 3, 9)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('An Inconvenient Truth', 'Davis Guggenheim', '2006-05-24', 'An Inconvenient Truth focuses on Al Gore and on his travels in 
support of his efforts to educate the public about the severity of the climate crisis. Gore says, "Ive been trying to tell this story for a 
long time and I feel as if Ive failed to get the message across."[6] The film documents a Keynote presentation (which Gore refers to 
as "the slide show") that Gore has presented throughout the world. It intersperses Gores exploration of data and predictions regarding 
climate change and its potential for disaster with his own life story.', 4.75, 3, 11)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Reservoir Dogs', 'Quentin Tarantino', '1992-10-23', 'Eight men eat breakfast at a Los Angeles diner before their planned diamond 
heist. Six of them use aliases: Mr. Blonde (Michael Madsen), Mr. Blue (Eddie Bunker), Mr. Brown (Quentin Tarantino), Mr. Orange (Tim 
Roth), Mr. Pink (Steve Buscemi), and Mr. White (Harvey Keitel). With them are gangster Joe Cabot (Lawrence Tierney), the organizer 
of the heist and his son, "Nice Guy" Eddie (Chris Penn).', 3.25, 5, 9)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Good Will Hunting', 'Gus Van Sant', '1997-12-05', '20-year-old Will Hunting (Matt Damon) of South Boston has a genius-level 
intellect but chooses to work as a janitor at the Massachusetts Institute of Technology and spend his free time with his friends Chuckie 
Sullivan (Ben Affleck), Billy McBride (Cole Hauser) and Morgan OMally (Casey Affleck). When Fields Medal-winning combinatorialist 
Professor Gerald Lambeau (Stellan Skarsgård) posts a difficult problem taken from algebraic graph theory as a challenge for his 
graduate students to solve, Will solves the problem quickly but anonymously. Lambeau posts a much more difficult problem and 
chances upon Will solving it, but Will flees. Will meets Skylar (Minnie Driver), a British student about to graduate from Harvard 
University and pursue a graduate degree at Stanford University School of Medicine in California.', 3.25, 5, 9) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Air Force One', 'Wolfgang Petersen', '1997-07-25', 'A joint military operation between Russian and American special operations 
forces ends with the capture of General Ivan Radek (Jürgen Prochnow), the dictator of a rogue terrorist regime in Kazakhstan that 
had taken possession of an arsenal of former Soviet nuclear weapons, who is now taken to a Russian maximum security prison. Three 
weeks later, a diplomatic dinner is held in Moscow to celebrate the capture of the Kazakh dictator, at which President of the United 
States James Marshall (Harrison Ford) expresses his remorse that action had not been taken sooner to prevent the suffering that 
Radek caused. He also vows that his administration will take a firmer stance against despotism and refuse to negotiate with terrorists.', 
3.25, 5, 3) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Hurricane', 'Norman Jewison', '1999-12-29', 'The film tells the story of middleweight boxer Rubin "Hurricane" Carter, whose 
conviction for a Paterson, New Jersey triple murder was set aside after he had spent almost 20 years in prison. Narrating Carters life, 
the film concentrates on the period between 1966 and 1985. It describes his fight against the conviction for triple murder and how he 
copes with nearly twenty years in prison. In a parallel plot, an underprivileged youth from Brooklyn, Lesra Martin, becomes interested 
in Carters life and destiny after reading Carters autobiography, and convinces his Canadian foster family to commit themselves to his 
case. The story culminates with Carters legal teams successful pleas to Judge H. Lee Sarokin of the United States District Court for 
the District of New Jersey.', 3.25, 5, 5)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Children of Men', 'Alfonso Cuarón', '2006-09-22', 'In 2027, after 18 years of worldwide female infertility, civilization is on the 
brink of collapse as humanity faces the grim reality of extinction. The United Kingdom, one of the few stable nations with a 
functioning government, has been deluged by asylum seekers from around the world, fleeing the chaos and war which has taken hold 
in most countries. In response, Britain has become a militarized police state as British forces round up and detain immigrants. 
Kidnapped by an immigrants rights group known as the Fishes, former activist turned cynical bureaucrat Theo Faron (Clive Owen) is 
brought to its leader, his estranged American wife Julian Taylor (Julianne Moore), from whom he separated after their son died from 
a flu pandemic in 2008.', 4.75, 3, 5)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bring It On', 'Peyton Reed', '2000-08-25', 'Torrance Shipman (Kirsten Dunst) anxiously dreams about her first day of senior year. 
Her boyfriend, Aaron (Richard Hillman), has left for college, and her cheerleading squad, the Toros, is aiming for a sixth consecutive 
national title. Team captain, "Big Red" (Lindsay Sloane), is graduating and Torrance is elected to take her place. Shortly after her 
election, however, a team member is injured and can no longer compete. Torrance replaces her with Missy Pantone (Eliza Dushku), 
a gymnast who recently transferred to the school with her brother, Cliff (Jesse Bradford). Torrance and Cliff develop a flirtatious 
friendship.', 4.75, 3, 5)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Elephant Man', 'David Lynch', '1980-10-03', 'London Hospital surgeon Frederick Treves discovers John Merrick in a Victorian 
freak show in Londons East End, where he is managed by the brutish Bytes. Merrick is deformed to the point that he must wear a hood 
and cap when in public, and Bytes claims he is an imbecile. Treves is professionally intrigued by Merricks condition and pays Bytes to 
bring him to the Hospital so that he can examine him. There, Treves presents Merrick to his colleagues in a lecture theatre, displaying 
him as a physiological curiosity. Treves draws attention to Merricks most life-threatening deformity, his abnormally large skull, which 
compels him to sleep with his head resting upon his knees, as the weight of his skull would asphyxiate him if he were to ever lie down. 
On Merricks return, Bytes beats him severely enough that a sympathetic apprentice alerts Treves, who returns him to the hospital. 
Bytes accuses Treves of likewise exploiting Merrick for his own ends, leading the surgeon to resolve to do what he can to help the 
unfortunate man.', 3.25, 5, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Fly', 'David Cronenberg', '1986-08-15', 'Seth Brundle (Jeff Goldblum), a brilliant but eccentric scientist, meets Veronica 
Quaife (Geena Davis), a journalist for Particle magazine, at a meet-the-press event held by Bartok Science Industries, the company 
that provides funding for Brundles work. Seth takes Veronica back to the warehouse that serves as both his home and laboratory, and 
shows her a project that will change the world: a set of "Telepods" that allows instantaneous teleportation of an object from one pod 
to another. Veronica eventually agrees to document Seths work. Although the Telepods can transport inanimate objects, they do not 
work properly on living things, as is demonstrated when a live baboon is turned inside-out during an experiment. Seth and Veronica 
begin a romantic relationship. Their first sexual encounter provides inspiration for Seth, who successfully reprograms the Telepod 
computer to cope with living creatures, and teleports a second baboon with no apparent harm.', 3.25, 5, 6) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Frances', 'Graeme Clifford', '1982-12-03', 'Born in Seattle, Washington, Frances Elena Farmer is a rebel from a young age, 
winning a high school award by writing an essay called "God Dies" in 1931. Later that decade, she becomes controversial again when 
she wins (and accepts) an all-expenses-paid trip to the USSR in 1935. Determined to become an actress, Frances is equally determined 
not to play the Hollywood game: she refuses to acquiesce to publicity stunts, and insists upon appearing on screen without makeup. 
Her defiance attracts the attention of Broadway playwright Clifford Odets, who convinces Frances that her future rests with the 
Group Theatre.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Young Frankenstein', 'Mel Brooks', '1974-12-15', 'Dr. Frederick Frankenstein (Gene Wilder) is a physician lecturer at an American 
medical school and engaged to the tightly wound Elizabeth (Madeline Kahn). He becomes exasperated when anyone brings up the 
subject of his grandfather, the infamous mad scientist. To disassociate himself from his legacy, Frederick insists that his surname be 
pronounced "Fronk-en-steen".', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Top Gun', 'Tony Scott', '1986-05-16', 'United States Naval Aviator Lieutenant Pete "Maverick" Mitchell (Tom Cruise) flies the 
F-14A Tomcat off USS Enterprise (CVN-65), with Radar Intercept Officer ("RIO") Lieutenant (Junior Grade) Nick "Goose" Bradshaw 
(Anthony Edwards). At the start of the film, wingman "Cougar" (John Stockwell) and his radar intercept officer "Merlin" (Tim Robbins), 
intercept MiG-28s over the Indian Ocean. During the engagement, one of the MiGs manages to get missile lock on Cougar. While 
Maverick realizes that the MiG "(would) have fired by now", if he really meant to fight, and drives off the MiGs, Cougar is too shaken 
afterward to land, despite being low on fuel. Maverick defies orders and shepherds Cougar back to the carrier, despite also being low 
on fuel. After they land, Cougar retires ("turns in his wings"), stating that he has been holding on "too tight" and has lost "the edge", 
almost orphaning his newborn child, whom he has never seen.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Crimson Tide', 'Tony Scott', '1995-05-12', 'In post-Soviet Russia, military units loyal to Vladimir Radchenko, an ultranationalist, 
have taken control of a nuclear missile installation and are threatening nuclear war if either the American or Russian governments 
attempt to confront him.', 3.25, 5, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Rock', 'Michael Bay', '1996-06-07', 'A group of rogue U.S. Force Recon Marines led by disenchanted Brigadier General Frank 
Hummel (Ed Harris) seize a stockpile of deadly VX gas–armed rockets from a heavily guarded US Navy bunker, reluctantly leaving one 
of their men to die in the process, when a bead of the gas falls and breaks. The next day, Hummel and his men, along with more 
renegade Marines Captains Frye (Gregory Sporleder) and Darrow (Tony Todd) (who have never previously served under Hummel) seize 
control of Alcatraz during a guided tour and take 81 tourists hostage in the prison cells. Hummel threatens to launch the stolen 
rockets against the population of San Francisco if the media is alerted or payment is refused or unless the government pays $100 
million in ransom and reparations to the families of Recon Marines, (using money the U.S. earned via illegal weapons sales) who died 
on illegal, clandestine missions under his command and whose deaths were not honored.', 3.25, 5, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Con Air', 'Simon West', '1997-06-06', 'Former U.S. Army Ranger Cameron Poe is sentenced to a maximum-security federal 
penitentiary for using excessive force and killing a drunk man who had been attempting to assault his pregnant wife, Tricia. Eight 
years later, Poe is paroled on good behavior, and eager to see his daughter Casey whom he has never met. Poe is arranged to be flown 
back home to Alabama on the C-123 Jailbird where he will be released on landing; several other prisoners, including his diabetic 
cellmate and friend Mike "Baby-O" ODell and criminal mastermind Cyrus "The Virus" Grissom, as well as Grissoms right-hand man, 
Nathan Jones, are also being transported to a new Supermax prison. DEA agent Duncan Malloy wishes to bring aboard one of his agents, 
Willie Sims, as a prisoner to coax more information out of drug lord Francisco Cindino before he is incarcerated. Vince Larkin, the U.S. 
Marshal overseeing the transfer, agrees to it, but is unaware that Malloy has armed Sims with a gun.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('National Treasure', 'Jon Turteltaub', '2004-11-19', 'Benjamin Franklin Gates (Nicolas Cage) is a historian and amateur cryptologist, 
and the youngest descendant of a long line of treasure hunters. Though Bens father, Patrick Henry Gates, tries to discourage Ben from 
following in the family line, as he had spent over 20 years looking for the national treasure, attracting ridicule on the family name, 
young Ben is encouraged onward by a clue, "The secret lies with Charlotte", from his grandfather John Adams Gates in 1974, that 
could lead to the fabled national treasure hidden by the Founding Fathers of the United States and Freemasons during the American 
Revolutionary War that was entrusted to his family by Charles Carroll of Carrollton in 1832 before his death to find, and protect the 
family name.', 4.75, 3, 15)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Hope Floats', 'Forest Whitaker', '1998-05-29', 'Birdee Pruitt (Sandra Bullock) is a Chicago housewife who is invited onto a talk 
show under the pretense of getting a free makeover. The makeover she is given is hardly what she has in mind...as she is ambushed 
with the revelation that her husband Bill has been having an affair behind her back with her best friend Connie. Humiliated on 
national television, Birdee and her daughter Bernice (Mae Whitman) move back to Birdees hometown of Smithville, Texas with 
Birdees eccentric mother Ramona (Gena Rowlands) to try to make a fresh start. As Birdee and Bernice leave Chicago, Birdee gives 
Bernice a letter from her father, telling Bernice how much he misses her.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Gun Shy', 'Eric Blakeney', '2000-02-04', 'Charlie Mayeaux (Liam Neeson) is an undercover DEA agent suffering from anxiety and 
gastrointestinal problems after a bust gone wrong. During the aforementioned incident, his partner was killed and he found himself 
served up on a platter of watermelon with a gun shoved in his face just before back-up arrived. Charlie, once known for his ease and 
almost "magical" talent on the job, is finding it very hard to return to work. His requests to be taken off the case or retired are denied 
by his bosses, Lonny Ward (Louis Giambalvo) and Dexter Helvenshaw (Mitch Pileggi) as so much time was put into his cover. Charlie 
works with the dream of one day retiring to Ocean Views, a luxury housing complex with servants and utilities.', 4.75, 3, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Miss Congeniality', 'Donald Petrie', '2000-12-22', 'The film opens at a school where a boy is picking on another boy. We see 
Gracie Hart (Mary Ashleigh Green) as a child who beats up the bully and tries to help the victim (whom she liked), who instead 
criticizes her by saying he disliked her because he did not want a girl to help him. She promptly punches the boy in the nose and sulks 
in the playground.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Murder by Numbers', 'Barbet Schroeder', '2002-04-19', 'Richard Haywood, a wealthy and popular high-schooler, secretly teams 
up with another rich kid in his class, brilliant nerd Justin "Bonaparte" Pendleton. His erudition, especially in forensic matters, allows 
them to plan elaborately perfect murders as a perverse form of entertainment. Meeting in a deserted resort, they drink absinthe, 
smoke, and joke around, but pretend to have an adversarial relationship while at school. Justin, in particular, behaves strangely, 
writing a paper about how crime is freedom and vice versa, and creating a composite photograph of himself and Richard.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Two Weeks Notice', 'Marc Lawrence', '2002-12-18', 'Lucy Kelson (Sandra Bullock) is a liberal lawyer who specializes in 
environmental law in New York City. George Wade (Hugh Grant) is an immature billionaire real estate tycoon who has almost 
everything and knows almost nothing. Lucys hard work and devotion to others contrast sharply with Georges world weary 
recklessness and greed.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Miss Congeniality 2: Armed and Fabulous', 'John Pasquin', '2005-03-24', 'Three weeks after the events of the first film, FBI agent 
Gracie Hart (Sandra Bullock) has become a celebrity after she infiltrated a beauty pageant on her last assignment. Her fame results in 
her cover being blown while she is trying to prevent a bank heist.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('All About Steve', 'Phil Traill', '2009-09-04', 'Mary Horowitz, a crossword puzzle writer for the Sacramento Herald, is socially 
awkward and considers her pet hamster her only true friend.  Her parents decide to set her up on a blind date. Marys expectations 
are low, as she tells her hamster. However, she is extremely surprised when her date turns out to be handsome and charming Steve 
Miller, a cameraman for the television news network CCN. However, her feelings for Steve are not reciprocated. After an attempt at 
an intimate moment fails, in part because of her awkwardness and inability to stop talking about vocabulary, Steve fakes a phone call 
about covering the news out of town. Trying to get Mary out of his truck, he tells her he wishes she could be there.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Nightmare Before Christmas', 'Henry Selick', '1993-10-29', 'Halloween Town is a dream world filled with citizens such as 
deformed monsters, ghosts, ghouls, goblins, vampires, werewolves and witches. Jack Skellington ("The Pumpkin King") leads them in a 
frightful celebration every Halloween, but he has grown tired of the same routine year after year. Wandering in the forest outside the 
town center, he accidentally opens a portal to "Christmas Town". Impressed by the feeling and style of Christmas, Jack presents his 
findings and his (somewhat limited) understanding of the festivities to the Halloween Town residents. They fail to grasp his meaning 
and compare everything he says to their idea of Halloween. He reluctantly decides to play along and announces that they will take 
over Christmas.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cabin Boy', 'Adam Resnick', '1994-01-07', 'Nathaniel Mayweather (Chris Elliott) is a snobbish, self-centered, virginal man. He is 
invited by his father to sail to Hawaii aboard the Queen Catherine. After annoying the driver, he is forced to walk the rest of the way.  
Nathaniel makes a wrong turn into a small fishing village where he meets the imbecilic cabin boy/first mate Kenny (Andy Richter). He 
thinks the ship, The Filthy Whore, is a theme boat. It is not until the next morning that Captain Greybar (Ritch Brinkley) finds 
Nathaniel in his room and explains that the boat will not return to dry land for three months.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('James and the Giant Peach', 'Henry Selick', '1996-04-12', 'In the 1930s, James Henry Trotter is a young boy who lives with his 
parents by the sea in the United Kingdom. On Jamess birthday, they plan to go to New York City and visit the Empire State Building, 
the tallest building in the world. However, his parents are later killed by a ghostly rhinoceros from the sky and finds himself living 
with his two cruel aunts, Spiker and Sponge.', 3.25, 5, 15)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('9', 'Shane Acker', '2009-09-09', 'Prior to the events of film, a scientist is ordered by his dictator to create a machine in the 
apparent name of progress. The Scientist uses his own intellect to create the B.R.A.I.N., a thinking robot. However, the dictator 
quickly seizes it and integrates it into the Fabrication Machine, an armature that can construct an army of war machines to destroy 
the dictators enemies. Lacking a soul, the Fabrication Machine is corrupted and exterminates all organic life using toxic gas. In 
desperation, the Scientist uses alchemy to create nine homunculus-like rag dolls known as Stitchpunks using portions of his own soul 
via a talisman, but dies as a result.', 4.75, 3, 16)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bruce Almighty', 'Tom Shadyac', '2003-05-23', 'Bruce Nolan (Jim Carrey) is a television field reporter for Eyewitness News on 
WKBW-TV in Buffalo, New York but desires to be the news anchorman. When he is passed over for the promotion in favour of his 
co-worker rival, Evan Baxter (Steve Carell), he becomes furious and rages during an interview at Niagara Falls, his resulting actions 
leading to his suspension from the station, followed by a series of misfortunes such as getting assaulted by a gang of thugs for standing 
up for a blind man they are beating up as he later on meets with them again and asks them to apologize for beating him up. Bruce 
complains to God that Hes "the one that should be fired".', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Fun with Dick and Jane', 'Dean Parisot', '2005-12-21', 'In January 2000, Dick Harper (Jim Carrey) has been promoted to VP of 
Communication for his company, Globodyne. Soon after, he is asked to appear on the show Money Life, where host Sam Samuels and 
then independent presidential candidate Ralph Nader dub him and all the companys employees as "perverters of the American dream" 
and claim that Globodyne helps the super rich get even wealthier. As they speak, the companys stock goes into a free-fall and is soon 
worthless, along with all the employees pensions, which are in Globodynes stock. Dick arrives home to find his excited wife Jane (Téa 
Leoni), who informs him that she took his advice and quit her job in order to spend more time with their son Billy.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Blood Simple', 'Joel Coen', '1985-01-18', 'Julian Marty (Dan Hedaya), the owner of a Texas bar, suspects his wife Abby (Frances 
McDormand) is having an affair with one of his bartenders, Ray (John Getz). Marty hires private detective Loren Visser (M. Emmet 
Walsh) to take photos of Ray and Abby in bed at a local motel. The morning after their tryst, Marty makes a menacing phone call to 
them, making it clear he is aware of their relationship.', 3.25, 5, 18)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Raising Arizona', 'Joel Coen', '1987-03-06', 'Criminal Herbert I. "Hi" McDunnough (Nicolas Cage) and policewoman Edwina "Ed" 
(Holly Hunter) meet after she takes the mugshots of the recidivist. With continued visits, Hi learns that Eds fiancé has left her. Hi 
proposes to her after his latest release from prison, and the two get married. They move into a desert mobile home, and Hi gets a job 
in a machine shop. They want to have children, but Ed discovers that she is infertile. Due to His criminal record, they cannot adopt a 
child. The couple learns of the "Arizona Quints," sons of locally famous furniture magnate Nathan Arizona (Trey Wilson); Hi and Ed 
kidnap one of the five babies, whom they believe to be Nathan Junior.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Barton Fink', 'Joel Coen', '1991-08-21', 'Barton Fink (John Turturro) is enjoying the success of his first Broadway play, Bare 
Ruined Choirs. His agent informs him that Capitol Pictures in Hollywood has offered a thousand dollars per week to write movie 
scripts. Barton hesitates, worried that moving to California would separate him from "the common man", his focus as a writer. He 
accepts the offer, however, and checks into the Hotel Earle, a large and unusually deserted building. His room is sparse and draped in 
subdued colors; its only decoration is a small painting of a woman on the beach, arm raised to block the sun.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Fargo', 'Joel Coen', '1996-03-08', 'In the winter of 1987, Minneapolis automobile salesman Jerry Lundegaard (Macy) is in financial 
trouble. Jerry is introduced to criminals Carl Showalter (Buscemi) and Gaear Grimsrud (Stormare) by Native American ex-convict 
Shep Proudfoot (Reevis), a mechanic at his dealership. Jerry travels to Fargo, North Dakota and hires the two men to kidnap his wife 
Jean (Rudrüd) in exchange for a new 1987 Oldsmobile Cutlass Ciera and half of the $80,000 ransom. However, Jerry intends to demand 
a much larger sum from his wealthy father-in-law Wade Gustafson (Presnell) and keep most of the money for himself.', 3.25, 5, 19)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('No Country for Old Men', 'Joel Coen', '2007-11-09', 'West Texas in June 1980 is desolate, wide open country, and Ed Tom Bell 
(Tommy Lee Jones) laments the increasing violence in a region where he, like his father and grandfather before him, has risen to the 
office of sheriff.', 4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Vanilla Sky', 'Cameron Crowe', '2001-12-14', 'David Aames (Tom Cruise) was the wealthy owner of a large publishing firm in New 
York City after the death of his father. From a prison cell, David, in a prosthetic mask, tells his story to psychiatrist Dr. Curtis McCabe 
(Kurt Russell): enjoying the bachelor lifestyle, he is introduced to Sofia Serrano (Penélope Cruz) by his best friend, Brian Shelby (Jason 
Lee), at a party. David and Sofia spend a night together talking, and fall in love. When Davids former girlfriend, Julianna "Julie" 
Gianni (Cameron Diaz), hears of Sofia, she attempts to kill herself and David in a car crash. While Julie dies, David remains alive, but 
his face is horribly disfigured, forcing him to wear a mask to hide the injuries. Unable to come to grips with the mask, he gets drunk 
on a night out at a bar with Sofia, and he is left to wallow in the street.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Narc', 'Joe Carnahan', '2003-01-10', 'Undercover narcotics officer Nick Tellis (Jason Patric) chases a drug dealer through the 
streets of Detroit after Tellis identity has been discovered. After the dealer fatally injects a bystander (whom Tellis was forced to 
leave behind) with drugs, he holds a young child hostage. Tellis manages to shoot and kill the dealer before he can hurt the child. 
However, one of the bullets inadvertently hits the childs pregnant mother, causing her to eventually miscarry.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Others', 'Alejandro Amenábar', '2001-08-10', 'Grace Stewart (Nicole Kidman) is a Catholic mother who lives with her two 
small children in a remote country house in the British Crown Dependency of Jersey, in the immediate aftermath of World War II. The 
children, Anne (Alakina Mann) and Nicholas (James Bentley), have an uncommon disease, xeroderma pigmentosa, characterized by 
photosensitivity, so their lives are structured around a series of complex rules designed to protect them from inadvertent exposure to 
sunlight.', 4.75, 3, 21)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Minority Report', 'Steven Spielberg', '2002-06-21', 'In April 2054, Captain John Anderton (Tom Cruise) is chief of the highly 
controversial Washington, D.C., PreCrime police force. They use future visions generated by three "precogs", mutated humans with 
precognitive abilities, to stop murders; because of this, the city has been murder-free for six years. Though Anderton is a respected 
member of the force, he is addicted to Clarity, an illegal psychoactive drug he began using after the disappearance of his son Sean. 
With the PreCrime force poised to go nationwide, the system is audited by Danny Witwer (Colin Farrell), a member of the United 
States Justice Department. During the audit, the precogs predict that Anderton will murder a man named Leo Crow in 36 hours. 
Believing the incident to be a setup by Witwer, who is aware of Andertons addiction, Anderton attempts to hide the case and quickly 
departs the area before Witwer begins a manhunt for him.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('War of the Worlds', 'Steven Spielberg', '2005-06-29', 'Ray Ferrier (Tom Cruise) is a container crane operator at a New Jersey 
port and is estranged from his children. He is visited by his ex-wife, Mary Ann (Miranda Otto), who drops off the children, Rachel 
(Dakota Fanning) and Robbie (Justin Chatwin), as she is going to visit her parents in Boston. Meanwhile T.V. reports tell of bizarre 
lightning storms which have knocked off power in parts of the Ukraine. Robbie takes Rays car out without his permission, so Ray 
starts searching for him. Outside, Ray notices a strange wall cloud, which starts to send out powerful lightning strikes, disabling all 
electronic devices in the area, including cars, forcing Robbie to come back. Ray heads down the street to investigate. He stops at a 
garage and tells Manny the local mechanic, to replace the solenoid on a dead car.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Last Samurai', 'The Last Samurai', '2003-12-05', 'In 1876, Captain Nathan Algren (Tom Cruise) is traumatized by his massacre 
of Native Americans in the Indian Wars and has become an alcoholic to stave off the memories. Algren is approached by former 
colleague Zebulon Gant (Billy Connolly), who takes him to meet Algrens former Colonel Bagley (Tony Goldwyn), whom Algren despises 
for ordering the massacre. On behalf of businessman Mr. Omura (Masato Harada), Bagley offers Algren a job training conscripts of the 
new Meiji government of Japan to suppress a samurai rebellion that is opposed to Western influence, led by Katsumoto (Ken Watanabe). 
Despite the painful ironies of crushing another tribal rebellion, Algren accepts solely for payment. In Japan he keeps a journal and is 
accompanied by British translator Simon Graham (Timothy Spall), who intends to write an account of Japanese culture, centering on 
the samurai.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Shattered Glass', 'Billy Ray', '2003-10-31', 'Stephen Randall Glass is a reporter/associate editor at The New Republic, a 
well-respected magazine located in Washington, DC., where he is making a name for himself for writing the most colorful stories. 
His editor, Michael Kelly, is revered by his young staff. When David Keene (at the time Chairman of the American Conservative Union) 
questions Glass description of minibars and the drunken antics of Young Republicans at a convention, Kelly backs his reporter when 
Glass admits to one mistake but says the rest is true.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Independence Day', 'Roland Emmerich', '1996-07-02', 'On July 2, an enormous alien ship enters Earths orbit and deploys 36 
smaller saucer-shaped ships, each 15 miles wide, which position themselves over major cities around the globe. David Levinson (Jeff 
Goldblum), a satellite technician for a television network in Manhattan, discovers transmissions hidden in satellite links that he 
realizes the aliens are using to coordinate an attack. David and his father Julius (Judd Hirsch) travel to the White House and warn his 
ex-wife, White House Communications Director Constance Spano (Margaret Colin), and President Thomas J. Whitmore (Bill Pullman) of 
the attack. The President, his daughter, portions of his Cabinet and the Levinsons narrowly escape aboard Air Force One as the alien 
spacecraft destroy Washington D.C., New York City, Los Angeles and other cities around the world.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Godzilla', 'Roland Emmerich', '1998-05-20', 'Following a nuclear incident in French Polynesia, a lizards nest is irradiated by the 
fallout of subsequent radiation. Decades later, a Japanese fishing vessel is suddenly attacked by an enormous sea creature in the 
South Pacific ocean; only one seaman survives. Traumatized, he is questioned by a mysterious Frenchman in a hospital regarding 
what he saw, to which he replies, "Gojira".', 3.25, 5, 24)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Patriot', 'Roland Emmerich', '2000-06-30', 'During the American Revolution in 1776, Benjamin Martin (Mel Gibson), a 
veteran of the French and Indian War and widower with seven children, is called to Charleston to vote in the South Carolina General 
Assembly on a levy supporting the Continental Army. Fearing war against Great Britain, Benjamin abstains. Captain James Wilkins 
(Adam Baldwin) votes against and joins the Loyalists. A supporting vote is nonetheless passed and against his fathers wishes, 
Benjamins eldest son Gabriel (Heath Ledger) joins the Continental Army.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Constantine', 'Francis Lawrence', '2005-02-18', 'John Constantine is an exorcist who lives in Los Angeles. Born with the power to 
see angels and demons on Earth, he committed suicide at age 15 after being unable to cope with his visions. Constantine was revived 
by paramedics but spent two minutes in Hell. He knows that because of his actions his soul is condemned to damnation when he dies, 
and has recently learned that he has developed cancer as a result of his smoking habit.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Shooter', 'Antoine Fuqua', '2007-03-23', 'Bob Lee Swagger (Mark Wahlberg) is a retired U.S. Marine Gunnery Sergeant who served 
as a Force Recon Scout Sniper. He reluctantly leaves a self-imposed exile from his isolated mountain home in the Wind River Range at 
the request of Colonel Isaac Johnson (Danny Glover). Johnson appeals to Swaggers expertise and patriotism to help track down an 
assassin who plans on shooting the president from a great distance with a high-powered rifle. Johnson gives him a list of three cities 
where the President is scheduled to visit so Swagger can determine if an attempt could be made at any of them.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Aviator', 'Martin Scorsese', '2004-12-25', 'In 1914, nine-year-old Howard Hughes is being bathed by his mother. She warns 
him of disease, afraid that he will succumb to a flu outbreak: "You are not safe." By 1927, Hughes (Leonardo DiCaprio) has inherited 
his familys fortune, is living in California. He hires Noah Dietrich (John C. Reilly) to run the Hughes Tool Company.', 4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The 11th Hour', 'Nadia Conners', '2007-08-17', 'With contributions from over 50 politicians, scientists, and environmental 
activists, including former Soviet leader Mikhail Gorbachev, physicist Stephen Hawking, Nobel Prize winner Wangari Maathai, and 
journalist Paul Hawken, the film documents the grave problems facing the planets life systems. Global warming, deforestation, mass 
species extinction, and depletion of the oceans habitats are all addressed. The films premise is that the future of humanity is in 
jeopardy.', 4.75, 3, 22)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Romancing the Stone', 'Robert Zemeckis', '1984-03-30', 'Joan Wilder (Kathleen Turner) is a lonely romance novelist in New York 
City who receives a treasure map mailed to her by her recently-murdered brother-in-law. Her widowed sister, Elaine (Mary Ellen 
Trainor), calls Joan and begs her to come to Cartagena, Colombia because Elaine has been kidnapped by bumbling antiquities 
smugglers Ira (Zack Norman) and Ralph (Danny DeVito), and the map is to be the ransom.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('One Flew Over the Cuckoos Nest', 'Miloš Forman', '1975-11-19', 'In 1963 Oregon, Randle Patrick "Mac" McMurphy (Jack Nicholson), 
a recidivist anti-authoritarian criminal serving a short sentence on a prison farm for statutory rape of a 15-year-old girl, is transferred 
to a mental institution for evaluation. Although he does not show any overt signs of mental illness, he hopes to avoid hard labor and 
serve the rest of his sentence in a more relaxed hospital environment.', 3.25, 5, 12)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Risky Business', 'Paul Brickman', '1983-08-05', 'Joel Goodson (Tom Cruise) is a high school student who lives with his wealthy 
parents in the North Shore area of suburban Chicago. His father wants him to attend Princeton University, so Joels mother tells him 
to tell the interviewer, Bill Rutherford, about his participation in Future Enterprisers, an extracurricular activity in which students 
work in teams to create small businesses.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Beetlejuice', 'Tim Burton', '1988-03-30', 'Barbara and Adam Maitland decide to spend their vacation decorating their idyllic New 
England country home in fictional Winter River, Connecticut. While the young couple are driving back from town, Barbara swerves to 
avoid a dog wandering the roadway and crashes through a covered bridge, plunging into the river below. They return home and, 
based on such subtle clues as their lack of reflection in the mirror and their discovery of a Handbook for the Recently Deceased, begin 
to suspect they might be dead. Adam attempts to leave the house to retrace his steps but finds himself in a strange, otherworldly 
dimension referred to as "Saturn", covered in sand and populated by enormous sandworms.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Hamlet 2', 'Andrew Fleming', '2008-08-22', 'Dana Marschz (Steve Coogan) is a recovering alcoholic and failed actor who has 
become a high school drama teacher in Tucson, Arizona, "where dreams go to die". Despite considering himself an inspirational figure, 
he only has two enthusiastic students, Rand (Skylar Astin) and Epiphany (Phoebe Strole), and a history of producing poorly-received 
school plays that are essentially stage adaptations of popular Hollywood films (his latest being Erin Brockovich). When the new term 
begins, a new intake of students are forced to transfer into his class as it is the only remaining arts elective available due to budget 
cutbacks; they are mostly unenthusiastic and unconvinced by Dana’s pretentions, and Dana comes into conflict with Octavio (Joseph 
Julian Soria), one of the new students.', 4.75, 3, 16)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Michael', 'Nora Ephron', '1996-12-25', 'Vartan Malt (Bob Hoskins) is the editor of a tabloid called the National Mirror that 
specializes in unlikely stories about celebrities and frankly unbelievable tales about ordinary folkspersons. When Malt gets word that a 
woman is supposedly harboring an angel in a small town in Iowa, he figures that this might be up the Mirrors alley, so he sends out 
three people to get the story – Frank Quinlan (William Hurt), a reporter whose career has hit the skids; Huey Driscoll (Robert Pastorelli), 
a photographer on the verge of losing his job (even though he owns the Mirrors mascot Sparky the Wonder Dog); and Dorothy Winters 
(Andie MacDowell), a self-styled "angel expert" (actually a dog trainer hired by Malt to eventually replace Driscoll).', 3.25, 5, 7)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Youve Got Mail', 'Nora Ephron', '1998-12-18', 'Kathleen Kelly (Meg Ryan) is involved with Frank Navasky (Greg Kinnear), a 
leftist postmodernist newspaper writer for the New York Observer whos always in search of an opportunity to root for the underdog. 
While Frank is devoted to his typewriter, Kathleen prefers her laptop and logging into her AOL e-mail account. There, using the screen 
name Shopgirl, she reads an e-mail from "NY152", the screen name of Joe Fox (Tom Hanks). In her reading of the e-mail, she reveals 
the boundaries of the online relationship; no specifics, including no names, career or class information, or family connections. Joe 
belongs to the Fox family which runs Fox Books — a chain of "mega" bookstores similar to Borders or Barnes & Noble.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bewitched', 'Nora Ephron', '2005-06-24', 'Jack Wyatt (Will Ferrell) is a narcissistic actor who is approached to play the role of 
Darrin in a remake of the classic sitcom Bewitched but insists that an unknown play Samantha.  Isabel Bigelow (Nicole Kidman) is an 
actual witch who decides she wants to be normal and moves to Los Angeles to start a new life and becomes friends with her neighbor 
Maria (Kristin Chenoweth). She goes to a bookstore to learn how to get a job after seeing an advertisement of Ed McMahon on TV.', 
4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Love Story', 'Arthur Hiller', '1970-12-16', 'The film tells of Oliver Barrett IV, who comes from a family of wealthy and 
well-respected Harvard University graduates. At Radcliffe library, the Harvard student meets and falls in love with Jennifer Cavalleri, 
a working-class, quick-witted Radcliffe College student. Upon graduation from college, the two decide to marry against the wishes of 
Olivers father, who thereupon severs ties with his son.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Godfather', 'Francis Ford Coppola', '1972-03-15', 'On the day of his only daughters wedding, Vito Corleone hears requests in 
his role as the Godfather, the Don of a New York crime family. Vitos youngest son, Michael, in Marine Corps khakis, introduces his 
girlfriend, Kay Adams, to his family at the sprawling reception. Vitos godson Johnny Fontane, a popular singer, pleads for help in 
securing a coveted movie role, so Vito dispatches his consigliere, Tom Hagen, to the abrasive studio head, Jack Woltz, to secure the 
casting. Woltz is unmoved until the morning he wakes up in bed with the severed head of his prized stallion.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Chinatown', 'Roman Polanski', '1974-06-20', 'A woman identifying herself as Evelyn Mulwray (Ladd) hires private investigator 
J.J. "Jake" Gittes (Nicholson) to perform matrimonial surveillance on her husband Hollis I. Mulwray (Zwerling), the chief engineer for 
the Los Angeles Department of Water and Power. Gittes tails him, hears him publicly oppose the creation of a new reservoir, and 
shoots photographs of him with a young woman (Palmer) that hit the front page of the following days paper. Upon his return to his 
office he is confronted by a beautiful woman who, after establishing that the two of them have never met, irately informs him that 
she is in fact Evelyn Mulwray (Dunaway) and he can expect a lawsuit.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Saint', 'Phillip Noyce', '1997-04-04', 'At the Saint Ignatius Orphanage, a rebellious boy named John Rossi refers to himself 
as "Simon Templar" and leads a group of fellow orphans as they attempt to run away to escape their harsh treatment. When Simon is 
caught by the head priest, he witnesses the tragic death of a girl he had taken a liking to when she accidentally falls from a balcony.', 
3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Alexander', 'Oliver Stone', '2004-11-24', 'The film is based on the life of Alexander the Great, King of Macedon, who conquered 
Asia Minor, Egypt, Persia and part of Ancient India. Shown are some of the key moments of Alexanders youth, his invasion of the 
mighty Persian Empire and his death. It also outlines his early life, including his difficult relationship with his father Philip II of 
Macedon, his strained feeling towards his mother Olympias, the unification of the Greek city-states and the two Greek Kingdoms 
(Macedon and Epirus) under the Hellenic League,[3] and the conquest of the Persian Empire in 331 BC. It also details his plans to 
reform his empire and the attempts he made to reach the end of the then known world.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Terminator Salvation', 'Joseph McGinty Nichol', '2009-05-21', 'In 2003, Doctor Serena Kogan (Helena Bonham Carter) of 
Cyberdyne Systems convinces death row inmate Marcus Wright (Sam Worthington) to sign his body over for medical research following 
his execution by lethal injection. One year later the Skynet system is activated, perceives humans as a threat to its own existence, 
and eradicates much of humanity in the event known as "Judgment Day" (as depicted in Terminator 3: Rise of the Machines).', 
4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('I Know What You Did Last Summer', 'Jim Gillespie', '1997-10-17', 'Four friends, Helen Shivers (Sarah Michelle Gellar), Julie 
James (Jennifer Love Hewitt), Barry Cox (Ryan Phillippe), and Ray Bronson (Freddie Prinze Jr.) go out of town to celebrate Helens 
winning the Miss Croaker pageant. Returning in Barrys new car, they hit and apparently kill a man, who is unknown to them. They 
dump the corpse in the ocean and agree to never discuss again what had happened.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Score', 'Frank Oz', '2001-07-13', 'After nearly being caught on a routine burglary, master safe-cracker Nick Wells (Robert De 
Niro) decides the time has finally come to retire. Nicks flight attendant girlfriend, Diane (Angela Bassett), encourages this decision, 
promising to fully commit to their relationship if he does indeed go straight. Nick, however, is lured into taking one final score by his 
fence Max (Marlon Brando) The job, worth a $4 million pay off to Nick, is to steal a valuable French sceptre, which was being smuggled 
illegally into the United States through Canada but was accidentally discovered and kept at the Montréal Customs House.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Sleepy Hollow', 'Tim Burton', '1999-11-19', 'In 1799, New York City, Ichabod Crane is a 24-year-old police officer. He is dispatched 
by his superiors to the Westchester County hamlet of Sleepy Hollow, New York, to investigate a series of brutal slayings in which the 
victims have been found decapitated: Peter Van Garrett, wealthy farmer and landowner; his son Dirk; and the widow Emily Winship, 
who secretly wed Van Garrett and was pregnant before being murdered. A pioneer of new, unproven forensic techniques such as 
finger-printing and autopsies, Crane arrives in Sleepy Hollow armed with his bag of scientific tools only to be informed by the towns 
elders that the murderer is not of flesh and blood, rather a headless undead Hessian mercenary from the American Revolutionary War 
who rides at night on a massive black steed in search of his missing head.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('I Still Know What You Did Last Summer', 'Danny Cannon', '1998-11-13', 'Julie James is getting over the events of the previous 
film, which nearly claimed her life. She hasnt been doing well in school and is continuously having nightmares involving Ben Willis 
(Muse Watson) still haunting her. Approaching the 4th July weekend, Ray (Freddie Prinze, Jr.) surprises her at her dorm. He invites 
her back up to Southport for the Croaker queen pageant. She objects and tells him she has not healed enough to go back. He tells her 
she needs some space away from Southport and him and leaves in a rush. After getting inside,she sits on her bed and looks at a picture 
of her deceased best friend Helen (Sarah Michelle Gellar), who died the previous summer at the hands of the fisherman.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard with a Vengeance', 'John McTiernan', '1995-05-19', 'In New York City, a bomb detonates destroying the Bonwit Teller 
department store. A man calling himself "Simon" phones Major Case Unit Inspector Walter Cobb of the New York City Police 
Department, claiming responsibility for the bomb. He demands that suspended police officer Lt. John McClane be dropped in Harlem 
wearing a sandwich board that says "I hate Niggers". Harlem shop owner Zeus Carver spots McClane and tries to get him off the street 
before he is killed, but a gang of black youths attack the pair, who barely escape. Returning to the station, they learn that Simon is 
believed to have stolen several thousand gallons of an explosive compound. Simon calls again demanding McClane and Carver put 
themselves through a series of "games" to prevent more explosions.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Terminator 3: Rise of the Machines', 'Jonathan Mostow', '2003-07-02', 'For nine years, John Connor (Nick Stahl) has been living 
off-the-grid in Los Angeles. Although Judgment Day did not occur on August 29, 1997, John does not believe that the prophesied war 
between humans and Skynet has been averted. Unable to locate John, Skynet sends a new model of Terminator, the T-X (Kristanna 
Loken), back in time to July 24, 2004 to kill his future lieutenants in the human Resistance. A more advanced model than previous 
Terminators, the T-X has an endoskeleton with built-in weaponry, a liquid metal exterior similar to the T-1000, and the ability to 
control other machines. The Resistance sends a reprogrammed T-850 model 101 Terminator (Arnold Schwarzenegger) back in time to 
protect the T-Xs targets, including Kate Brewster (Claire Danes) and John.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Amityville Horror', 'Andrew Douglas', '2005-04-15', 'On November 13, 1974, at 3:15am, Ronald DeFeo, Jr. shot and killed his 
family at their home, 112 Ocean Avenue in Amityville, New York. He killed five members of his family in their beds, but his youngest 
sister, Jodie, had been killed in her bedroom closet. He claimed that he was persuaded to kill them by voices he had heard in the 
house.', 4.75, 3, 21)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Runaway Bride', 'Garry Marshall', '1999-07-30', 'Maggie Carpenter (Julia Roberts) is a spirited and attractive young woman who 
has had a number of unsuccessful relationships. Maggie, nervous of being married, has left a trail of fiances. It seems, shes left three 
men waiting for her at the altar on their wedding day (all of which are caught on tape), receiving tabloid fame and the dubious 
nickname "The Runaway Bride".', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Jumanji', 'Joe Johnston', '1995-12-15', 'In 1869, two boys bury a chest in a forest near Keene, New Hampshire. A century later, 
12-year-old Alan Parrish flees from a gang of bullies to a shoe factory owned by his father, Sam, where he meets his friend Carl Bentley, 
one of Sams employees. When Alan accidentally damages a machine with a prototype sneaker Carl hopes to present, Carl takes the 
blame and loses his job. Outside the factory, after the bullies beat Alan up and steal his bicycle, Alan follows the sound of tribal 
drumbeats to a construction site and finds the chest, containing a board game called Jumanji.', 3.25, 5, 24)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Revenge of the Nerds', 'Jeff Kanew', '1984-07-20', 'Best friends and nerds Lewis Skolnick (Robert Carradine) and Gilbert Lowe 
(Anthony Edwards) enroll in Adams College to study computer science. The Alpha Betas, a fraternity to which many members of the 
schools football team belong, carelessly burn down their own house and seize the freshmen dorm for themselves. The college allows 
the displaced freshmen, living in the gymnasium, to join fraternities or move to other housing. Lewis, Gilbert, and other outcasts who 
cannot join a fraternity renovate a dilapidated home to serve as their own fraternity house.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Easy Rider', 'Dennis Hopper', '1969-07-14', 'The protagonists are two freewheeling hippies: Wyatt (Fonda), nicknamed "Captain 
America", and Billy (Hopper). Fonda and Hopper said that these characters names refer to Wyatt Earp and Billy the Kid.[4] Wyatt 
dresses in American flag-adorned leather (with an Office of the Secretary of Defense Identification Badge affixed to it), while Billy 
dresses in Native American-style buckskin pants and shirts and a bushman hat. The former is appreciative of help and of others, while 
the latter is often hostile and leery of outsiders.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Braveheart', 'Mel Gibson', '1995-05-24', 'In 1280, King Edward "Longshanks" (Patrick McGoohan) invades and conqueres Scotland 
following the death of Scotlands King Alexander III who left no heir to the throne. Young William Wallace witnesses the treachery of 
Longshanks, survives the death of his father and brother, and is taken abroad to Rome by his Uncle Argyle (Brian Cox) where he is 
educated.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Passion of the Christ', 'Mel Gibson', '2004-02-25', 'The film opens in Gethsemane as Jesus prays and is tempted by Satan, 
while his apostles, Peter, James and John sleep. After receiving thirty pieces of silver, one of Jesus other apostles, Judas, approaches 
with the temple guards and betrays Jesus with a kiss on the cheek. As the guards move in to arrest Jesus, Peter cuts off the ear of 
Malchus, but Jesus heals the ear. As the apostles flee, the temple guards arrest Jesus and beat him during the journey to the 
Sanhedrin. John tells Mary and Mary Magdalene of the arrest while Peter follows Jesus at a distance. Caiaphas holds trial over the 
objection of some of the other priests, who are expelled from the court.', 4.75, 3, 8)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Finding Neverland', 'Marc Forster', '2004-11-12', 'The story focuses on Scottish writer J. M. Barrie, his platonic relationship with 
Sylvia Llewelyn Davies, and his close friendship with her sons, who inspire the classic play Peter Pan, or The Boy Who Never Grew Up.', 
4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Bourne Identity', 'Doug Liman', '2002-06-14', 'In the Mediterranean Sea near Marseille, Italian fishermen rescue an 
unconscious man floating adrift with two gunshot wounds in his back. The boats medic finds a tiny laser projector surgically implanted 
under the unknown mans skin at the level of the hip. When activated, the laser projector displays the number of a safe deposit box in 
Zürich. The man wakes up and discovers he is suffering from extreme memory loss. Over the next few days on the ship, the man finds 
he is fluent in several languages and has unusual skills, but cannot remember anything about himself or why he was in the sea. When 
the ship docks, he sets off to investigate the safe deposit box.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Cider House Rules', 'Lasse Hallström', '1999-12-17', 'Homer Wells (Tobey Maguire), an orphan, is the films protagonist. He 
grew up in an orphanage directed by Dr. Wilbur Larch (Michael Caine) after being returned twice by foster parents. His first foster 
parents thought he was too quiet and the second parents beat him. Dr. Larch is addicted to ether and is also secretly an abortionist. 
Larch trains Homer in obstetrics and abortions as an apprentice, despite Homer never even having attended high school.', 3.25, 5, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Field of Dreams', 'Phil Alden Robinson', '1989-04-21', 'While walking in his cornfield, novice farmer Ray Kinsella hears a voice 
that whispers, "If you build it, he will come", and sees a baseball diamond. His wife, Annie, is skeptical, but she allows him to plow 
under his corn to build the field.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Waterworld', 'Kevin Reynolds', '1995-07-28', 'In the future (year 2500), the polar ice caps have melted due to the global warming, 
and the sea level has risen hundreds of meters, covering every continent and turning Earth into a water planet. Human population 
has been scattered across the ocean in individual, isolated communities consisting of artificial islands and mostly decrepit sea vessels. 
It was so long since the events that the humans eventually forgot that there were continents in the first place and that there is a 
place on Earth called "the Dryland", a mythical place.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard', 'John McTiernan', '1988-07-15', 'New York City Police Department detective John McClane arrives in Los Angeles to 
reconcile with his estranged wife, Holly. Limo driver Argyle drives McClane to the Nakatomi Plaza building to meet Holly at a company 
Christmas party. While McClane changes clothes, the party is disrupted by the arrival of German terrorist Hans Gruber and his heavily 
armed group: Karl, Franco, Tony, Theo, Alexander, Marco, Kristoff, Eddie, Uli, Heinrich, Fritz and James. The group seizes the 
skyscraper and secure those inside as hostages, except for McClane, who manages to slip away, armed with only his service sidearm, a 
Beretta 92F pistol.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard 2', 'Renny Harlin', '1990-07-04', 'On Christmas Eve, two years after the Nakatomi Tower Incident, John McClane is 
waiting at Washington Dulles International Airport for his wife Holly to arrive from Los Angeles, California. Reporter Richard Thornburg, 
who exposed Hollys identity to Hans Gruber in Die Hard, is assigned a seat across the aisle from her. While in the airport bar, McClane 
spots two men in army fatigues carrying a package; one of the men has a gun. Suspicious, he follows them into the baggage area. After 
a shootout, he kills one of the men while the other escapes. Learning the dead man is a mercenary thought to have been killed in 
action, McClane believes hes stumbled onto a nefarious plot. He relates his suspicions to airport police Captain Carmine Lorenzo, but 
Lorenzo refuses to listen and has McClane thrown out of his office.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Splash', 'Ron Howard', '1984-03-09', 'As an eight year-old boy, Allen Bauer (David Kreps) is vacationing with his family near Cape 
Cod. While taking a sight-seeing tour on a ferry, he gazes into the ocean and sees something below the surface that fascinates him. 
Allen jumps into the water, even though he cannot swim. He grasps the hands of a girl who is inexplicably under the water with him 
and an instant connection forms between the two. Allen is quickly pulled to the surface by the deck hands and the two are separated, 
though apparently no one else sees the girl. After the ferry moves off, Allen continues to look back at the girl in the water, who cries 
at their separation.', 3.25, 5, 25)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Parenthood', 'Ron Howard', '1989-08-02', 'Gil Buckman (Martin), a neurotic sales executive, is trying to balance his family and 
his career in suburban St. Louis. When he finds out that his eldest son, Kevin, has emotional problems and needs therapy, and that his 
two younger children, daughter Taylor and youngest son Justin, both have issues as well, he begins to blame himself and questions his 
abilities as a father. When his wife, Karen (Steenburgen), becomes pregnant with their fourth child, he is unsure he can handle it.', 
3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Apollo 13', 'Ron Howard', '1995-06-30', 'On July 20, 1969, veteran astronaut Jim Lovell (Tom Hanks) hosts a party for other 
astronauts and their families, who watch on television as their colleague Neil Armstrong takes his first steps on the Moon during the 
Apollo 11 mission. Lovell, who orbited the Moon on Apollo 8, tells his wife Marilyn (Kathleen Quinlan) that he intends to return, to 
walk on its surface.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Dr. Seuss How the Grinch Stole Christmas', 'Ron Howard', '2000-11-17', 'In the microscopic city of Whoville, everyone celebrates 
Christmas with much happiness and joy, with the exception of the cynical and misanthropic Grinch (Jim Carrey), who despises 
Christmas and the Whos with great wrath and occasionally pulls dangerous and harmful practical jokes on them. As a result, no one 
likes or cares for him.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('A Beautiful Mind', 'Ron Howard', '2001-12-21', 'In 1947, John Nash (Russell Crowe) arrives at Princeton University. He is co-recipient, 
with Martin Hansen (Josh Lucas), of the prestigious Carnegie Scholarship for mathematics. At a reception he meets a group of other 
promising math and science graduate students, Richard Sol (Adam Goldberg), Ainsley (Jason Gray-Stanford), and Bender (Anthony Rapp). 
He also meets his roommate Charles Herman (Paul Bettany), a literature student, and an unlikely friendship begins.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Da Vinci Code', 'Ron Howard', '2006-05-19', 'In Paris, Jacques Saunière is pursued through the Louvres Grand Gallery by 
albino monk Silas (Paul Bettany), demanding the Priorys clef de voûte or "keystone." Saunière confesses the keystone is kept in the 
sacristy of Church of Saint-Sulpice "beneath the Rose" before Silas shoots him. At the American University of Paris, Robert Langdon, a 
symbologist who is a guest lecturer on symbols and the sacred feminine, is summoned to the Louvre to view the crime scene. He 
discovers the dying Saunière has created an intricate display using black light ink and his own body and blood. Captain Bezu Fache 
(Jean Reno) asks him for his interpretation of the puzzling scene.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Simpsons Movie', 'David Silverman', '2007-07-27', 'While performing on Lake Springfield, rock band Green Day are killed 
when pollution in the lake dissolves their barge, following an audience revolt after frontman Billie Joe Armstrong proposes an 
environmental discussion. At a memorial service, Grampa has a prophetic vision in which he predicts the impending doom of the town, 
but only Marge takes it seriously. Then Homer dares Bart to skate naked and he does so. Lisa and an Irish boy named Colin, with whom 
she has fallen in love, hold a meeting where they convince the town to clean up the lake.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Crash', 'Paul Haggis', '2005-05-06', 'Los Angeles detectives Graham Waters (Don Cheadle) and his partner Ria (Jennifer Esposito) 
approach a crime scene investigation. Waters exits the car to check out the scene. One day prior, Farhad (Shaun Toub), a Persian 
shop owner, and his daughter, Dorri (Bahar Soomekh), argue with each other in front of a gun store owner as Farhad tries to buy a 
revolver. The shop keeper grows impatient and orders an infuriated Farhad outside. Dorri defiantly finishes the gun purchase, which 
she had opposed. The purchase entitles the buyer to one box of ammunition. She selects a red box.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Million Dollar Baby', 'Clint Eastwood', '2004-12-15', 'Margaret "Maggie" Fitzgerald, a waitress from a Missouri town in the Ozarks, 
shows up in the Hit Pit, a run-down Los Angeles gym which is owned and operated by Frankie Dunn, a brilliant but only marginally 
successful boxing trainer. Maggie asks Dunn to train her, but he angrily responds that he "doesnt train girls."', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Letters from Iwo Jima', 'Clint Eastwood', '2006-12-20', 'In 2005, Japanese archaeologists explore tunnels on Iwo Jima, where they 
find something buried in the soil.  The film flashes back to Iwo Jima in 1944. Private First Class Saigo is grudgingly digging trenches on 
the beach. A teenage baker, Saigo has been conscripted into the Imperial Japanese Army despite his youth and his wifes pregnancy. 
Saigo complains to his friend Private Kashiwara that they should let the Americans have Iwo Jima. Overhearing them, an enraged 
Captain Tanida starts brutally beating them for "conspiring with unpatriotic words." At the same time, General Tadamichi Kuribayashi 
arrives to take command of the garrison and immediately begins an inspection of the island defenses.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cast Away', 'Robert Zemeckis', '2000-12-07', 'In 1995, Chuck Noland (Tom Hanks) is a time-obsessed systems analyst, who travels 
worldwide resolving productivity problems at FedEx depots. He is in a long-term relationship with Kelly Frears (Helen Hunt), whom he 
lives with in Memphis, Tennessee. Although the couple wants to get married, Chucks busy schedule interferes with their relationship. 
A Christmas with relatives is interrupted by Chuck being summoned to resolve a problem in Malaysia.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cloverfield', 'J. J. Abrams', '2008-01-18', 'The film is presented as found footage from a personal video 
camera recovered by the United States Department of Defense. A disclaimer text states that the footage is of a case 
designated "Cloverfield" and was found in the area "formerly known as Central Park". The video consists chiefly of 
segments taped the night of Friday, May 22, 2009. The newer segments were taped over older video that is shown 
occasionally.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Mission: Impossible III', 'J. J. Abrams', '2006-05-05', 'Ethan Hunt (Tom Cruise) has retired from active field work for the 
Impossible Missions Force (IMF) and instead trains new recruits while settling down with his fiancée Julia Meade (Michelle Monaghan), 
a nurse at a local hospital who is unaware of Ethans past. Ethan is approached by fellow IMF agent John Musgrave (Billy Crudup) 
about a mission for him: rescue one of Ethans protégés, Lindsey Farris (Keri Russell), who was captured while investigating arms 
dealer Owen Davian (Philip Seymour Hoffman). Musgrave has already prepared a team for Ethan, consisting of Declan Gormley 
(Jonathan Rhys Meyers), Zhen Lei (Maggie Q), and his old partner Luther Stickell (Ving Rhames), in Berlin, Germany.', 4.75, 3, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Star Trek', 'J. J. Abrams', '2009-05-08', 'In 2233, the Federation starship USS Kelvin is investigating a "lightning storm" in space. 
A Romulan ship, the Narada, emerges from the storm and attacks the Kelvin. Naradas first officer, Ayel, demands that the Kelvins 
Captain Robau come aboard to discuss a cease fire. Once aboard, Robau is questioned about an "Ambassador Spock", who he states 
that he is "not familiar with", as well as the current stardate, after which the Naradas commander, Nero, flies into a rage and kills 
him, before continuing to attack the Kelvin. The Kelvins first officer, Lieutenant Commander George Kirk, orders the ships personnel 
evacuated via shuttlecraft, including his pregnant wife, Winona. Kirk steers the Kelvin on a collision course at the cost of his own life, 
while Winona gives birth to their son, James Tiberius Kirk.', 4.75, 3, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Halloween', 'John Carpenter', '1978-10-25', 'On Halloween night, 1963, in fictional Haddonfield, Illinois, 6-year-old Michael 
Myers (Will Sandin) murders his older teenage sister Judith (Sandy Johnson), stabbing her repeatedly with a butcher knife, after she 
had sex with her boyfriend. Fifteen years later, on October 30, 1978, Michael escapes the hospital in Smiths Grove, Illinois where he 
had been committed since the murder, stealing the car that was to take him to a court hearing.', 3.25, 5, 2)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Cable Guy', 'Ben Stiller', '1996-06-14', 'After a failed marriage proposal to his girlfriend Robin Harris (Leslie Mann), Steven 
M. Kovacs (Matthew Broderick) moves into his own apartment after they agree to spend some time apart. Enthusiastic cable guy 
Ernie "Chip" Douglas (Jim Carrey), an eccentric man with a lisp, installs his cable. Taking advice from his friend Rick (Jack Black), 
Steven bribes Chip to give him free movie channels, to which Chip agrees. Before he leaves, Chip gets Steven to hang out with him 
the next day and makes him one of his "preferred customers".', 3.25, 5, 3)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Anchorman: The Legend of Ron Burgundy', 'Adam McKay', '2004-07-09', 'In 1975, Ron Burgundy (Will Ferrell) is the famous and 
successful anchorman for San Diegos KVWN-TV Channel 4 Evening News. He works alongside his friends on the news team: 
fashion-oriented lead field reporter Brian Fantana (Paul Rudd), sportscaster Champion "Champ" Kind (David Koechner), and a "legally 
retarded" chief meteorologist Brick Tamland (Steve Carell). The team is notified by their boss, Ed Harken (Fred Willard), that their 
station has maintained its long-held status as the highest-rated news program in San Diego, leading them to throw a wild party. Ron 
sees an attractive blond woman and immediately tries to hit on her. After an awkward, failed pick-up attempt, the woman leaves.', 4.75, 3, 4) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The 40-Year-Old Virgin', 'Judd Apatow', '2005-08-19', 'Andy Stitzer (Steve Carell) is the eponymous 40-year-old virgin; he is 
involuntarily celibate. He lives alone, and is somewhat childlike; he collects action figures, plays video games, and his social life 
seems to consist of watching Survivor with his elderly neighbors. He works in the stockroom at an electronics store called SmartTech. 
When a friend drops out of a poker game, Andys co-workers David (Paul Rudd), Cal (Seth Rogen), and Jay (Romany Malco) reluctantly 
invite Andy to join them. At the game, when conversation turns to past sexual exploits, Andy desperately makes up a story, but when 
he compares the feel of a womans breast to a "bag of sand", he is forced to admit his virginity. Feeling sorry for him (but also 
generally mocking him), the group resolves to help Andy lose his virginity.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Knocked Up', 'Judd Apatow', '2007-06-01', 'Ben Stone (Seth Rogen) is laid-back and sardonic. He lives off funds received in 
compensation for an injury and sporadically works on a celebrity porn website with his roommates, in between smoking marijuana 
or going off with them at theme parks such as Knotts Berry Farm. Alison Scott (Katherine Heigl) is a career-minded woman who has 
just been given an on-air role with E! and is living in the pool house with her sister Debbies (Leslie Mann) family. While celebrating 
her promotion, Alison meets Ben at a local nightclub. After a night of drinking, they end up having sex. Due to a misunderstanding, 
they do not use protection: Alison uses the phrase "Just do it already" to encourage Ben to put the condom on, but he misinterprets 
this to mean to dispense with using one. The following morning, they quickly learn over breakfast that they have little in common 
and go their separate ways, which leaves Ben visibly upset.', 4.75, 3, 5) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Superbad', 'Greg Mottola', '2007-08-17', 'Seth (Jonah Hill) and Evan (Michael Cera) are two high school seniors who lament their 
virginity and poor social standing. Best friends since childhood, the two are about to go off to different colleges, as Seth did not get 
accepted into Dartmouth. After Seth is paired with Jules (Emma Stone) during Home-Ec class, she invites him to a party at her house 
later that night. Later, Fogell (Christopher Mintz-Plasse) comes up to the two and reveals his plans to obtain a fake ID during lunch. 
Seth uses this to his advantage and promises to bring alcohol to Jules party.', 4.75, 3, 3) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Donnie Darko', 'Richard Kelly', '2001-10-26', 'On October 2, 1988, Donnie Darko (Jake Gyllenhaal), a troubled teenager living in 
Middlesex, Virginia, is awakened and led outside by a figure in a monstrous rabbit costume, who introduces himself as "Frank" and 
tells him the world will end in 28 days, 6 hours, 42 minutes and 12 seconds. At dawn, Donnie awakens on a golf course and returns 
home to find a jet engine has crashed into his bedroom. His older sister, Elizabeth (Maggie Gyllenhaal), informs him the FAA 
investigators dont know where it came from.', 4.75, 3, 8)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Never Been Kissed', 'Raja Gosnell', '1999-04-09', 'Josie Geller (Drew Barrymore) is a copy editor for the Chicago Sun-Times who 
has never had a real relationship. One day during a staff meeting, the tyrannical editor-in-chief, Rigfort (Garry Marshall) assigns her 
to report undercover at a high school to help parents become more aware of their childrens lives.  Josie tells her brother Rob (David 
Arquette) about the assignment, and he reminds her that during high school she was a misfit labelled "Josie Grossie", a nickname 
which continues to haunt her.', 3.25, 5, 6)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Duplex', 'Danny DeVito', '2003-09-26', 'Alex Rose and Nancy Kendricks are a young, professional, New York couple in search of 
their dream home. When they finally find the perfect Brooklyn brownstone they are giddy with anticipation. The duplex is a dream 
come true, complete with multiple fireplaces, except for one thing: Mrs. Connelly, the old lady who lives on the rent-controlled top 
floor. Assuming she is elderly and ill, they take the apartment.', 4.75, 3, 9)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Music and Lyrics', 'Marc Lawrence', '2007-02-14', 'At the beginning of the film, Alex is a washed-up former pop star who is 
attempting to revive his career by hitching his career to the rising star of Cora Corman, a young megastar who has asked him to write 
a song titled "Way Back Into Love." During an unsuccessful attempt to come up with words for the song, he discovers that the woman 
who waters his plants, Sophie Fisher (Drew Barrymore), has a gift for writing lyrics. Sophie, a former creative writing student reeling 
from a disastrous romance with her former English professor Sloan Cates (Campbell Scott), initially refuses. Alex cajoles her into 
helping him by using a few quickly-chosen phrases she has given him as the basis for a song. Over the next few days, they grow closer 
while writing the words and music together, much to the delight of Sophies older sister Rhonda (Kristen Johnston), a huge fan of 
Alexs.', 4.75, 3, 10) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Charlies Angels', 'Joseph McGinty Nichol', '2000-11-03', 'Natalie Cook (Cameron Diaz), Dylan Sanders (Drew Barrymore) and 
Alex Munday (Lucy Liu) are the "Angels," three talented, tough, attractive women who work as private investigators for an unseen 
millionaire named Charlie (voiced by Forsythe). Charlie uses a speaker in his offices to communicate with the Angels, and his assistant 
Bosley (Bill Murray) works with them directly when needed.', 4.75, 3, 3)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Pulp Fiction', 'Quentin Tarantino', '1994-10-14', 'As Jules and Vincent eat breakfast in a coffee shop the discussion returns to 
Juless decision to retire. In a brief cutaway, we see "Pumpkin" and "Honey Bunny" shortly before they initiate the hold-up from the 
movies first scene. While Vincent is in the bathroom, the hold-up commences. "Pumpkin" demands all of the patrons valuables, 
including Juless mysterious case. Jules surprises "Pumpkin" (whom he calls "Ringo"), holding him at gunpoint. "Honey Bunny" (whose 
name turns out to be Yolanda), hysterical, trains her gun on Jules. Vincent emerges from the restroom with his gun trained on her, 
creating a Mexican standoff. Reprising his pseudo-biblical passage, Jules expresses his ambivalence about his life of crime.', 3.25, 5, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Kill Bill: Volume 1', 'Quentin Tarantino', '2003-10-03', '"The Bride", a former member of an assassination team who seeks 
revenge on her ex-colleagues who massacred members of her wedding party and tried to kill her. During the first movie she succeeds 
in killing two of the five members.', 4.75, 3, 9) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Kill Bill: Volume 2', 'Quentin Tarantino', '2004-04-16', '"The Bride", a former member of an assassination team who seeks 
revenge on her ex-colleagues who massacred members of her wedding party and tried to kill her. The film is often noted for its stylish 
direction and its homages to film genres such as Hong Kong martial arts films, Japanese chanbara films, Italian spaghetti westerns, 
girls with guns, and rape and revenge.', 4.75, 3, 9)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('An Inconvenient Truth', 'Davis Guggenheim', '2006-05-24', 'An Inconvenient Truth focuses on Al Gore and on his travels in 
support of his efforts to educate the public about the severity of the climate crisis. Gore says, "Ive been trying to tell this story for a 
long time and I feel as if Ive failed to get the message across."[6] The film documents a Keynote presentation (which Gore refers to 
as "the slide show") that Gore has presented throughout the world. It intersperses Gores exploration of data and predictions regarding 
climate change and its potential for disaster with his own life story.', 4.75, 3, 11)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Reservoir Dogs', 'Quentin Tarantino', '1992-10-23', 'Eight men eat breakfast at a Los Angeles diner before their planned diamond 
heist. Six of them use aliases: Mr. Blonde (Michael Madsen), Mr. Blue (Eddie Bunker), Mr. Brown (Quentin Tarantino), Mr. Orange (Tim 
Roth), Mr. Pink (Steve Buscemi), and Mr. White (Harvey Keitel). With them are gangster Joe Cabot (Lawrence Tierney), the organizer 
of the heist and his son, "Nice Guy" Eddie (Chris Penn).', 3.25, 5, 9)  
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Good Will Hunting', 'Gus Van Sant', '1997-12-05', '20-year-old Will Hunting (Matt Damon) of South Boston has a genius-level 
intellect but chooses to work as a janitor at the Massachusetts Institute of Technology and spend his free time with his friends Chuckie 
Sullivan (Ben Affleck), Billy McBride (Cole Hauser) and Morgan OMally (Casey Affleck). When Fields Medal-winning combinatorialist 
Professor Gerald Lambeau (Stellan Skarsgård) posts a difficult problem taken from algebraic graph theory as a challenge for his 
graduate students to solve, Will solves the problem quickly but anonymously. Lambeau posts a much more difficult problem and 
chances upon Will solving it, but Will flees. Will meets Skylar (Minnie Driver), a British student about to graduate from Harvard 
University and pursue a graduate degree at Stanford University School of Medicine in California.', 3.25, 5, 9) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Air Force One', 'Wolfgang Petersen', '1997-07-25', 'A joint military operation between Russian and American special operations 
forces ends with the capture of General Ivan Radek (Jürgen Prochnow), the dictator of a rogue terrorist regime in Kazakhstan that 
had taken possession of an arsenal of former Soviet nuclear weapons, who is now taken to a Russian maximum security prison. Three 
weeks later, a diplomatic dinner is held in Moscow to celebrate the capture of the Kazakh dictator, at which President of the United 
States James Marshall (Harrison Ford) expresses his remorse that action had not been taken sooner to prevent the suffering that 
Radek caused. He also vows that his administration will take a firmer stance against despotism and refuse to negotiate with terrorists.', 
3.25, 5, 3) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Hurricane', 'Norman Jewison', '1999-12-29', 'The film tells the story of middleweight boxer Rubin "Hurricane" Carter, whose 
conviction for a Paterson, New Jersey triple murder was set aside after he had spent almost 20 years in prison. Narrating Carters life, 
the film concentrates on the period between 1966 and 1985. It describes his fight against the conviction for triple murder and how he 
copes with nearly twenty years in prison. In a parallel plot, an underprivileged youth from Brooklyn, Lesra Martin, becomes interested 
in Carters life and destiny after reading Carters autobiography, and convinces his Canadian foster family to commit themselves to his 
case. The story culminates with Carters legal teams successful pleas to Judge H. Lee Sarokin of the United States District Court for 
the District of New Jersey.', 3.25, 5, 5)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Children of Men', 'Alfonso Cuarón', '2006-09-22', 'In 2027, after 18 years of worldwide female infertility, civilization is on the 
brink of collapse as humanity faces the grim reality of extinction. The United Kingdom, one of the few stable nations with a 
functioning government, has been deluged by asylum seekers from around the world, fleeing the chaos and war which has taken hold 
in most countries. In response, Britain has become a militarized police state as British forces round up and detain immigrants. 
Kidnapped by an immigrants rights group known as the Fishes, former activist turned cynical bureaucrat Theo Faron (Clive Owen) is 
brought to its leader, his estranged American wife Julian Taylor (Julianne Moore), from whom he separated after their son died from 
a flu pandemic in 2008.', 4.75, 3, 5)    
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bring It On', 'Peyton Reed', '2000-08-25', 'Torrance Shipman (Kirsten Dunst) anxiously dreams about her first day of senior year. 
Her boyfriend, Aaron (Richard Hillman), has left for college, and her cheerleading squad, the Toros, is aiming for a sixth consecutive 
national title. Team captain, "Big Red" (Lindsay Sloane), is graduating and Torrance is elected to take her place. Shortly after her 
election, however, a team member is injured and can no longer compete. Torrance replaces her with Missy Pantone (Eliza Dushku), 
a gymnast who recently transferred to the school with her brother, Cliff (Jesse Bradford). Torrance and Cliff develop a flirtatious 
friendship.', 4.75, 3, 5)   
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Elephant Man', 'David Lynch', '1980-10-03', 'London Hospital surgeon Frederick Treves discovers John Merrick in a Victorian 
freak show in Londons East End, where he is managed by the brutish Bytes. Merrick is deformed to the point that he must wear a hood 
and cap when in public, and Bytes claims he is an imbecile. Treves is professionally intrigued by Merricks condition and pays Bytes to 
bring him to the Hospital so that he can examine him. There, Treves presents Merrick to his colleagues in a lecture theatre, displaying 
him as a physiological curiosity. Treves draws attention to Merricks most life-threatening deformity, his abnormally large skull, which 
compels him to sleep with his head resting upon his knees, as the weight of his skull would asphyxiate him if he were to ever lie down. 
On Merricks return, Bytes beats him severely enough that a sympathetic apprentice alerts Treves, who returns him to the hospital. 
Bytes accuses Treves of likewise exploiting Merrick for his own ends, leading the surgeon to resolve to do what he can to help the 
unfortunate man.', 3.25, 5, 1) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Fly', 'David Cronenberg', '1986-08-15', 'Seth Brundle (Jeff Goldblum), a brilliant but eccentric scientist, meets Veronica 
Quaife (Geena Davis), a journalist for Particle magazine, at a meet-the-press event held by Bartok Science Industries, the company 
that provides funding for Brundles work. Seth takes Veronica back to the warehouse that serves as both his home and laboratory, and 
shows her a project that will change the world: a set of "Telepods" that allows instantaneous teleportation of an object from one pod 
to another. Veronica eventually agrees to document Seths work. Although the Telepods can transport inanimate objects, they do not 
work properly on living things, as is demonstrated when a live baboon is turned inside-out during an experiment. Seth and Veronica 
begin a romantic relationship. Their first sexual encounter provides inspiration for Seth, who successfully reprograms the Telepod 
computer to cope with living creatures, and teleports a second baboon with no apparent harm.', 3.25, 5, 6) 
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Frances', 'Graeme Clifford', '1982-12-03', 'Born in Seattle, Washington, Frances Elena Farmer is a rebel from a young age, 
winning a high school award by writing an essay called "God Dies" in 1931. Later that decade, she becomes controversial again when 
she wins (and accepts) an all-expenses-paid trip to the USSR in 1935. Determined to become an actress, Frances is equally determined 
not to play the Hollywood game: she refuses to acquiesce to publicity stunts, and insists upon appearing on screen without makeup. 
Her defiance attracts the attention of Broadway playwright Clifford Odets, who convinces Frances that her future rests with the 
Group Theatre.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Young Frankenstein', 'Mel Brooks', '1974-12-15', 'Dr. Frederick Frankenstein (Gene Wilder) is a physician lecturer at an American 
medical school and engaged to the tightly wound Elizabeth (Madeline Kahn). He becomes exasperated when anyone brings up the 
subject of his grandfather, the infamous mad scientist. To disassociate himself from his legacy, Frederick insists that his surname be 
pronounced "Fronk-en-steen".', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Top Gun', 'Tony Scott', '1986-05-16', 'United States Naval Aviator Lieutenant Pete "Maverick" Mitchell (Tom Cruise) flies the 
F-14A Tomcat off USS Enterprise (CVN-65), with Radar Intercept Officer ("RIO") Lieutenant (Junior Grade) Nick "Goose" Bradshaw 
(Anthony Edwards). At the start of the film, wingman "Cougar" (John Stockwell) and his radar intercept officer "Merlin" (Tim Robbins), 
intercept MiG-28s over the Indian Ocean. During the engagement, one of the MiGs manages to get missile lock on Cougar. While 
Maverick realizes that the MiG "(would) have fired by now", if he really meant to fight, and drives off the MiGs, Cougar is too shaken 
afterward to land, despite being low on fuel. Maverick defies orders and shepherds Cougar back to the carrier, despite also being low 
on fuel. After they land, Cougar retires ("turns in his wings"), stating that he has been holding on "too tight" and has lost "the edge", 
almost orphaning his newborn child, whom he has never seen.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Crimson Tide', 'Tony Scott', '1995-05-12', 'In post-Soviet Russia, military units loyal to Vladimir Radchenko, an ultranationalist, 
have taken control of a nuclear missile installation and are threatening nuclear war if either the American or Russian governments 
attempt to confront him.', 3.25, 5, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Rock', 'Michael Bay', '1996-06-07', 'A group of rogue U.S. Force Recon Marines led by disenchanted Brigadier General Frank 
Hummel (Ed Harris) seize a stockpile of deadly VX gas–armed rockets from a heavily guarded US Navy bunker, reluctantly leaving one 
of their men to die in the process, when a bead of the gas falls and breaks. The next day, Hummel and his men, along with more 
renegade Marines Captains Frye (Gregory Sporleder) and Darrow (Tony Todd) (who have never previously served under Hummel) seize 
control of Alcatraz during a guided tour and take 81 tourists hostage in the prison cells. Hummel threatens to launch the stolen 
rockets against the population of San Francisco if the media is alerted or payment is refused or unless the government pays $100 
million in ransom and reparations to the families of Recon Marines, (using money the U.S. earned via illegal weapons sales) who died 
on illegal, clandestine missions under his command and whose deaths were not honored.', 3.25, 5, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Con Air', 'Simon West', '1997-06-06', 'Former U.S. Army Ranger Cameron Poe is sentenced to a maximum-security federal 
penitentiary for using excessive force and killing a drunk man who had been attempting to assault his pregnant wife, Tricia. Eight 
years later, Poe is paroled on good behavior, and eager to see his daughter Casey whom he has never met. Poe is arranged to be flown 
back home to Alabama on the C-123 Jailbird where he will be released on landing; several other prisoners, including his diabetic 
cellmate and friend Mike "Baby-O" ODell and criminal mastermind Cyrus "The Virus" Grissom, as well as Grissoms right-hand man, 
Nathan Jones, are also being transported to a new Supermax prison. DEA agent Duncan Malloy wishes to bring aboard one of his agents, 
Willie Sims, as a prisoner to coax more information out of drug lord Francisco Cindino before he is incarcerated. Vince Larkin, the U.S. 
Marshal overseeing the transfer, agrees to it, but is unaware that Malloy has armed Sims with a gun.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('National Treasure', 'Jon Turteltaub', '2004-11-19', 'Benjamin Franklin Gates (Nicolas Cage) is a historian and amateur cryptologist, 
and the youngest descendant of a long line of treasure hunters. Though Bens father, Patrick Henry Gates, tries to discourage Ben from 
following in the family line, as he had spent over 20 years looking for the national treasure, attracting ridicule on the family name, 
young Ben is encouraged onward by a clue, "The secret lies with Charlotte", from his grandfather John Adams Gates in 1974, that 
could lead to the fabled national treasure hidden by the Founding Fathers of the United States and Freemasons during the American 
Revolutionary War that was entrusted to his family by Charles Carroll of Carrollton in 1832 before his death to find, and protect the 
family name.', 4.75, 3, 15)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Hope Floats', 'Forest Whitaker', '1998-05-29', 'Birdee Pruitt (Sandra Bullock) is a Chicago housewife who is invited onto a talk 
show under the pretense of getting a free makeover. The makeover she is given is hardly what she has in mind...as she is ambushed 
with the revelation that her husband Bill has been having an affair behind her back with her best friend Connie. Humiliated on 
national television, Birdee and her daughter Bernice (Mae Whitman) move back to Birdees hometown of Smithville, Texas with 
Birdees eccentric mother Ramona (Gena Rowlands) to try to make a fresh start. As Birdee and Bernice leave Chicago, Birdee gives 
Bernice a letter from her father, telling Bernice how much he misses her.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Gun Shy', 'Eric Blakeney', '2000-02-04', 'Charlie Mayeaux (Liam Neeson) is an undercover DEA agent suffering from anxiety and 
gastrointestinal problems after a bust gone wrong. During the aforementioned incident, his partner was killed and he found himself 
served up on a platter of watermelon with a gun shoved in his face just before back-up arrived. Charlie, once known for his ease and 
almost "magical" talent on the job, is finding it very hard to return to work. His requests to be taken off the case or retired are denied 
by his bosses, Lonny Ward (Louis Giambalvo) and Dexter Helvenshaw (Mitch Pileggi) as so much time was put into his cover. Charlie 
works with the dream of one day retiring to Ocean Views, a luxury housing complex with servants and utilities.', 4.75, 3, 13)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Miss Congeniality', 'Donald Petrie', '2000-12-22', 'The film opens at a school where a boy is picking on another boy. We see 
Gracie Hart (Mary Ashleigh Green) as a child who beats up the bully and tries to help the victim (whom she liked), who instead 
criticizes her by saying he disliked her because he did not want a girl to help him. She promptly punches the boy in the nose and sulks 
in the playground.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Murder by Numbers', 'Barbet Schroeder', '2002-04-19', 'Richard Haywood, a wealthy and popular high-schooler, secretly teams 
up with another rich kid in his class, brilliant nerd Justin "Bonaparte" Pendleton. His erudition, especially in forensic matters, allows 
them to plan elaborately perfect murders as a perverse form of entertainment. Meeting in a deserted resort, they drink absinthe, 
smoke, and joke around, but pretend to have an adversarial relationship while at school. Justin, in particular, behaves strangely, 
writing a paper about how crime is freedom and vice versa, and creating a composite photograph of himself and Richard.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Two Weeks Notice', 'Marc Lawrence', '2002-12-18', 'Lucy Kelson (Sandra Bullock) is a liberal lawyer who specializes in 
environmental law in New York City. George Wade (Hugh Grant) is an immature billionaire real estate tycoon who has almost 
everything and knows almost nothing. Lucys hard work and devotion to others contrast sharply with Georges world weary 
recklessness and greed.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Miss Congeniality 2: Armed and Fabulous', 'John Pasquin', '2005-03-24', 'Three weeks after the events of the first film, FBI agent 
Gracie Hart (Sandra Bullock) has become a celebrity after she infiltrated a beauty pageant on her last assignment. Her fame results in 
her cover being blown while she is trying to prevent a bank heist.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('All About Steve', 'Phil Traill', '2009-09-04', 'Mary Horowitz, a crossword puzzle writer for the Sacramento Herald, is socially 
awkward and considers her pet hamster her only true friend.  Her parents decide to set her up on a blind date. Marys expectations 
are low, as she tells her hamster. However, she is extremely surprised when her date turns out to be handsome and charming Steve 
Miller, a cameraman for the television news network CCN. However, her feelings for Steve are not reciprocated. After an attempt at 
an intimate moment fails, in part because of her awkwardness and inability to stop talking about vocabulary, Steve fakes a phone call 
about covering the news out of town. Trying to get Mary out of his truck, he tells her he wishes she could be there.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Nightmare Before Christmas', 'Henry Selick', '1993-10-29', 'Halloween Town is a dream world filled with citizens such as 
deformed monsters, ghosts, ghouls, goblins, vampires, werewolves and witches. Jack Skellington ("The Pumpkin King") leads them in a 
frightful celebration every Halloween, but he has grown tired of the same routine year after year. Wandering in the forest outside the 
town center, he accidentally opens a portal to "Christmas Town". Impressed by the feeling and style of Christmas, Jack presents his 
findings and his (somewhat limited) understanding of the festivities to the Halloween Town residents. They fail to grasp his meaning 
and compare everything he says to their idea of Halloween. He reluctantly decides to play along and announces that they will take 
over Christmas.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cabin Boy', 'Adam Resnick', '1994-01-07', 'Nathaniel Mayweather (Chris Elliott) is a snobbish, self-centered, virginal man. He is 
invited by his father to sail to Hawaii aboard the Queen Catherine. After annoying the driver, he is forced to walk the rest of the way.  
Nathaniel makes a wrong turn into a small fishing village where he meets the imbecilic cabin boy/first mate Kenny (Andy Richter). He 
thinks the ship, The Filthy Whore, is a theme boat. It is not until the next morning that Captain Greybar (Ritch Brinkley) finds 
Nathaniel in his room and explains that the boat will not return to dry land for three months.', 3.25, 5, 14)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('James and the Giant Peach', 'Henry Selick', '1996-04-12', 'In the 1930s, James Henry Trotter is a young boy who lives with his 
parents by the sea in the United Kingdom. On Jamess birthday, they plan to go to New York City and visit the Empire State Building, 
the tallest building in the world. However, his parents are later killed by a ghostly rhinoceros from the sky and finds himself living 
with his two cruel aunts, Spiker and Sponge.', 3.25, 5, 15)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('9', 'Shane Acker', '2009-09-09', 'Prior to the events of film, a scientist is ordered by his dictator to create a machine in the 
apparent name of progress. The Scientist uses his own intellect to create the B.R.A.I.N., a thinking robot. However, the dictator 
quickly seizes it and integrates it into the Fabrication Machine, an armature that can construct an army of war machines to destroy 
the dictators enemies. Lacking a soul, the Fabrication Machine is corrupted and exterminates all organic life using toxic gas. In 
desperation, the Scientist uses alchemy to create nine homunculus-like rag dolls known as Stitchpunks using portions of his own soul 
via a talisman, but dies as a result.', 4.75, 3, 16)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bruce Almighty', 'Tom Shadyac', '2003-05-23', 'Bruce Nolan (Jim Carrey) is a television field reporter for Eyewitness News on 
WKBW-TV in Buffalo, New York but desires to be the news anchorman. When he is passed over for the promotion in favour of his 
co-worker rival, Evan Baxter (Steve Carell), he becomes furious and rages during an interview at Niagara Falls, his resulting actions 
leading to his suspension from the station, followed by a series of misfortunes such as getting assaulted by a gang of thugs for standing 
up for a blind man they are beating up as he later on meets with them again and asks them to apologize for beating him up. Bruce 
complains to God that Hes "the one that should be fired".', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Fun with Dick and Jane', 'Dean Parisot', '2005-12-21', 'In January 2000, Dick Harper (Jim Carrey) has been promoted to VP of 
Communication for his company, Globodyne. Soon after, he is asked to appear on the show Money Life, where host Sam Samuels and 
then independent presidential candidate Ralph Nader dub him and all the companys employees as "perverters of the American dream" 
and claim that Globodyne helps the super rich get even wealthier. As they speak, the companys stock goes into a free-fall and is soon 
worthless, along with all the employees pensions, which are in Globodynes stock. Dick arrives home to find his excited wife Jane (Téa 
Leoni), who informs him that she took his advice and quit her job in order to spend more time with their son Billy.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Blood Simple', 'Joel Coen', '1985-01-18', 'Julian Marty (Dan Hedaya), the owner of a Texas bar, suspects his wife Abby (Frances 
McDormand) is having an affair with one of his bartenders, Ray (John Getz). Marty hires private detective Loren Visser (M. Emmet 
Walsh) to take photos of Ray and Abby in bed at a local motel. The morning after their tryst, Marty makes a menacing phone call to 
them, making it clear he is aware of their relationship.', 3.25, 5, 18)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Raising Arizona', 'Joel Coen', '1987-03-06', 'Criminal Herbert I. "Hi" McDunnough (Nicolas Cage) and policewoman Edwina "Ed" 
(Holly Hunter) meet after she takes the mugshots of the recidivist. With continued visits, Hi learns that Eds fiancé has left her. Hi 
proposes to her after his latest release from prison, and the two get married. They move into a desert mobile home, and Hi gets a job 
in a machine shop. They want to have children, but Ed discovers that she is infertile. Due to His criminal record, they cannot adopt a 
child. The couple learns of the "Arizona Quints," sons of locally famous furniture magnate Nathan Arizona (Trey Wilson); Hi and Ed 
kidnap one of the five babies, whom they believe to be Nathan Junior.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Barton Fink', 'Joel Coen', '1991-08-21', 'Barton Fink (John Turturro) is enjoying the success of his first Broadway play, Bare 
Ruined Choirs. His agent informs him that Capitol Pictures in Hollywood has offered a thousand dollars per week to write movie 
scripts. Barton hesitates, worried that moving to California would separate him from "the common man", his focus as a writer. He 
accepts the offer, however, and checks into the Hotel Earle, a large and unusually deserted building. His room is sparse and draped in 
subdued colors; its only decoration is a small painting of a woman on the beach, arm raised to block the sun.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Fargo', 'Joel Coen', '1996-03-08', 'In the winter of 1987, Minneapolis automobile salesman Jerry Lundegaard (Macy) is in financial 
trouble. Jerry is introduced to criminals Carl Showalter (Buscemi) and Gaear Grimsrud (Stormare) by Native American ex-convict 
Shep Proudfoot (Reevis), a mechanic at his dealership. Jerry travels to Fargo, North Dakota and hires the two men to kidnap his wife 
Jean (Rudrüd) in exchange for a new 1987 Oldsmobile Cutlass Ciera and half of the $80,000 ransom. However, Jerry intends to demand 
a much larger sum from his wealthy father-in-law Wade Gustafson (Presnell) and keep most of the money for himself.', 3.25, 5, 19)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('No Country for Old Men', 'Joel Coen', '2007-11-09', 'West Texas in June 1980 is desolate, wide open country, and Ed Tom Bell 
(Tommy Lee Jones) laments the increasing violence in a region where he, like his father and grandfather before him, has risen to the 
office of sheriff.', 4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Vanilla Sky', 'Cameron Crowe', '2001-12-14', 'David Aames (Tom Cruise) was the wealthy owner of a large publishing firm in New 
York City after the death of his father. From a prison cell, David, in a prosthetic mask, tells his story to psychiatrist Dr. Curtis McCabe 
(Kurt Russell): enjoying the bachelor lifestyle, he is introduced to Sofia Serrano (Penélope Cruz) by his best friend, Brian Shelby (Jason 
Lee), at a party. David and Sofia spend a night together talking, and fall in love. When Davids former girlfriend, Julianna "Julie" 
Gianni (Cameron Diaz), hears of Sofia, she attempts to kill herself and David in a car crash. While Julie dies, David remains alive, but 
his face is horribly disfigured, forcing him to wear a mask to hide the injuries. Unable to come to grips with the mask, he gets drunk 
on a night out at a bar with Sofia, and he is left to wallow in the street.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Narc', 'Joe Carnahan', '2003-01-10', 'Undercover narcotics officer Nick Tellis (Jason Patric) chases a drug dealer through the 
streets of Detroit after Tellis identity has been discovered. After the dealer fatally injects a bystander (whom Tellis was forced to 
leave behind) with drugs, he holds a young child hostage. Tellis manages to shoot and kill the dealer before he can hurt the child. 
However, one of the bullets inadvertently hits the childs pregnant mother, causing her to eventually miscarry.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Others', 'Alejandro Amenábar', '2001-08-10', 'Grace Stewart (Nicole Kidman) is a Catholic mother who lives with her two 
small children in a remote country house in the British Crown Dependency of Jersey, in the immediate aftermath of World War II. The 
children, Anne (Alakina Mann) and Nicholas (James Bentley), have an uncommon disease, xeroderma pigmentosa, characterized by 
photosensitivity, so their lives are structured around a series of complex rules designed to protect them from inadvertent exposure to 
sunlight.', 4.75, 3, 21)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Minority Report', 'Steven Spielberg', '2002-06-21', 'In April 2054, Captain John Anderton (Tom Cruise) is chief of the highly 
controversial Washington, D.C., PreCrime police force. They use future visions generated by three "precogs", mutated humans with 
precognitive abilities, to stop murders; because of this, the city has been murder-free for six years. Though Anderton is a respected 
member of the force, he is addicted to Clarity, an illegal psychoactive drug he began using after the disappearance of his son Sean. 
With the PreCrime force poised to go nationwide, the system is audited by Danny Witwer (Colin Farrell), a member of the United 
States Justice Department. During the audit, the precogs predict that Anderton will murder a man named Leo Crow in 36 hours. 
Believing the incident to be a setup by Witwer, who is aware of Andertons addiction, Anderton attempts to hide the case and quickly 
departs the area before Witwer begins a manhunt for him.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('War of the Worlds', 'Steven Spielberg', '2005-06-29', 'Ray Ferrier (Tom Cruise) is a container crane operator at a New Jersey 
port and is estranged from his children. He is visited by his ex-wife, Mary Ann (Miranda Otto), who drops off the children, Rachel 
(Dakota Fanning) and Robbie (Justin Chatwin), as she is going to visit her parents in Boston. Meanwhile T.V. reports tell of bizarre 
lightning storms which have knocked off power in parts of the Ukraine. Robbie takes Rays car out without his permission, so Ray 
starts searching for him. Outside, Ray notices a strange wall cloud, which starts to send out powerful lightning strikes, disabling all 
electronic devices in the area, including cars, forcing Robbie to come back. Ray heads down the street to investigate. He stops at a 
garage and tells Manny the local mechanic, to replace the solenoid on a dead car.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Last Samurai', 'The Last Samurai', '2003-12-05', 'In 1876, Captain Nathan Algren (Tom Cruise) is traumatized by his massacre 
of Native Americans in the Indian Wars and has become an alcoholic to stave off the memories. Algren is approached by former 
colleague Zebulon Gant (Billy Connolly), who takes him to meet Algrens former Colonel Bagley (Tony Goldwyn), whom Algren despises 
for ordering the massacre. On behalf of businessman Mr. Omura (Masato Harada), Bagley offers Algren a job training conscripts of the 
new Meiji government of Japan to suppress a samurai rebellion that is opposed to Western influence, led by Katsumoto (Ken Watanabe). 
Despite the painful ironies of crushing another tribal rebellion, Algren accepts solely for payment. In Japan he keeps a journal and is 
accompanied by British translator Simon Graham (Timothy Spall), who intends to write an account of Japanese culture, centering on 
the samurai.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Shattered Glass', 'Billy Ray', '2003-10-31', 'Stephen Randall Glass is a reporter/associate editor at The New Republic, a 
well-respected magazine located in Washington, DC., where he is making a name for himself for writing the most colorful stories. 
His editor, Michael Kelly, is revered by his young staff. When David Keene (at the time Chairman of the American Conservative Union) 
questions Glass description of minibars and the drunken antics of Young Republicans at a convention, Kelly backs his reporter when 
Glass admits to one mistake but says the rest is true.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Independence Day', 'Roland Emmerich', '1996-07-02', 'On July 2, an enormous alien ship enters Earths orbit and deploys 36 
smaller saucer-shaped ships, each 15 miles wide, which position themselves over major cities around the globe. David Levinson (Jeff 
Goldblum), a satellite technician for a television network in Manhattan, discovers transmissions hidden in satellite links that he 
realizes the aliens are using to coordinate an attack. David and his father Julius (Judd Hirsch) travel to the White House and warn his 
ex-wife, White House Communications Director Constance Spano (Margaret Colin), and President Thomas J. Whitmore (Bill Pullman) of 
the attack. The President, his daughter, portions of his Cabinet and the Levinsons narrowly escape aboard Air Force One as the alien 
spacecraft destroy Washington D.C., New York City, Los Angeles and other cities around the world.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Godzilla', 'Roland Emmerich', '1998-05-20', 'Following a nuclear incident in French Polynesia, a lizards nest is irradiated by the 
fallout of subsequent radiation. Decades later, a Japanese fishing vessel is suddenly attacked by an enormous sea creature in the 
South Pacific ocean; only one seaman survives. Traumatized, he is questioned by a mysterious Frenchman in a hospital regarding 
what he saw, to which he replies, "Gojira".', 3.25, 5, 24)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Patriot', 'Roland Emmerich', '2000-06-30', 'During the American Revolution in 1776, Benjamin Martin (Mel Gibson), a 
veteran of the French and Indian War and widower with seven children, is called to Charleston to vote in the South Carolina General 
Assembly on a levy supporting the Continental Army. Fearing war against Great Britain, Benjamin abstains. Captain James Wilkins 
(Adam Baldwin) votes against and joins the Loyalists. A supporting vote is nonetheless passed and against his fathers wishes, 
Benjamins eldest son Gabriel (Heath Ledger) joins the Continental Army.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Constantine', 'Francis Lawrence', '2005-02-18', 'John Constantine is an exorcist who lives in Los Angeles. Born with the power to 
see angels and demons on Earth, he committed suicide at age 15 after being unable to cope with his visions. Constantine was revived 
by paramedics but spent two minutes in Hell. He knows that because of his actions his soul is condemned to damnation when he dies, 
and has recently learned that he has developed cancer as a result of his smoking habit.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Shooter', 'Antoine Fuqua', '2007-03-23', 'Bob Lee Swagger (Mark Wahlberg) is a retired U.S. Marine Gunnery Sergeant who served 
as a Force Recon Scout Sniper. He reluctantly leaves a self-imposed exile from his isolated mountain home in the Wind River Range at 
the request of Colonel Isaac Johnson (Danny Glover). Johnson appeals to Swaggers expertise and patriotism to help track down an 
assassin who plans on shooting the president from a great distance with a high-powered rifle. Johnson gives him a list of three cities 
where the President is scheduled to visit so Swagger can determine if an attempt could be made at any of them.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Aviator', 'Martin Scorsese', '2004-12-25', 'In 1914, nine-year-old Howard Hughes is being bathed by his mother. She warns 
him of disease, afraid that he will succumb to a flu outbreak: "You are not safe." By 1927, Hughes (Leonardo DiCaprio) has inherited 
his familys fortune, is living in California. He hires Noah Dietrich (John C. Reilly) to run the Hughes Tool Company.', 4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The 11th Hour', 'Nadia Conners', '2007-08-17', 'With contributions from over 50 politicians, scientists, and environmental 
activists, including former Soviet leader Mikhail Gorbachev, physicist Stephen Hawking, Nobel Prize winner Wangari Maathai, and 
journalist Paul Hawken, the film documents the grave problems facing the planets life systems. Global warming, deforestation, mass 
species extinction, and depletion of the oceans habitats are all addressed. The films premise is that the future of humanity is in 
jeopardy.', 4.75, 3, 22)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Romancing the Stone', 'Robert Zemeckis', '1984-03-30', 'Joan Wilder (Kathleen Turner) is a lonely romance novelist in New York 
City who receives a treasure map mailed to her by her recently-murdered brother-in-law. Her widowed sister, Elaine (Mary Ellen 
Trainor), calls Joan and begs her to come to Cartagena, Colombia because Elaine has been kidnapped by bumbling antiquities 
smugglers Ira (Zack Norman) and Ralph (Danny DeVito), and the map is to be the ransom.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('One Flew Over the Cuckoos Nest', 'Miloš Forman', '1975-11-19', 'In 1963 Oregon, Randle Patrick "Mac" McMurphy (Jack Nicholson), 
a recidivist anti-authoritarian criminal serving a short sentence on a prison farm for statutory rape of a 15-year-old girl, is transferred 
to a mental institution for evaluation. Although he does not show any overt signs of mental illness, he hopes to avoid hard labor and 
serve the rest of his sentence in a more relaxed hospital environment.', 3.25, 5, 12)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Risky Business', 'Paul Brickman', '1983-08-05', 'Joel Goodson (Tom Cruise) is a high school student who lives with his wealthy 
parents in the North Shore area of suburban Chicago. His father wants him to attend Princeton University, so Joels mother tells him 
to tell the interviewer, Bill Rutherford, about his participation in Future Enterprisers, an extracurricular activity in which students 
work in teams to create small businesses.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Beetlejuice', 'Tim Burton', '1988-03-30', 'Barbara and Adam Maitland decide to spend their vacation decorating their idyllic New 
England country home in fictional Winter River, Connecticut. While the young couple are driving back from town, Barbara swerves to 
avoid a dog wandering the roadway and crashes through a covered bridge, plunging into the river below. They return home and, 
based on such subtle clues as their lack of reflection in the mirror and their discovery of a Handbook for the Recently Deceased, begin 
to suspect they might be dead. Adam attempts to leave the house to retrace his steps but finds himself in a strange, otherworldly 
dimension referred to as "Saturn", covered in sand and populated by enormous sandworms.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Hamlet 2', 'Andrew Fleming', '2008-08-22', 'Dana Marschz (Steve Coogan) is a recovering alcoholic and failed actor who has 
become a high school drama teacher in Tucson, Arizona, "where dreams go to die". Despite considering himself an inspirational figure, 
he only has two enthusiastic students, Rand (Skylar Astin) and Epiphany (Phoebe Strole), and a history of producing poorly-received 
school plays that are essentially stage adaptations of popular Hollywood films (his latest being Erin Brockovich). When the new term 
begins, a new intake of students are forced to transfer into his class as it is the only remaining arts elective available due to budget 
cutbacks; they are mostly unenthusiastic and unconvinced by Dana’s pretentions, and Dana comes into conflict with Octavio (Joseph 
Julian Soria), one of the new students.', 4.75, 3, 16)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Michael', 'Nora Ephron', '1996-12-25', 'Vartan Malt (Bob Hoskins) is the editor of a tabloid called the National Mirror that 
specializes in unlikely stories about celebrities and frankly unbelievable tales about ordinary folkspersons. When Malt gets word that a 
woman is supposedly harboring an angel in a small town in Iowa, he figures that this might be up the Mirrors alley, so he sends out 
three people to get the story – Frank Quinlan (William Hurt), a reporter whose career has hit the skids; Huey Driscoll (Robert Pastorelli), 
a photographer on the verge of losing his job (even though he owns the Mirrors mascot Sparky the Wonder Dog); and Dorothy Winters 
(Andie MacDowell), a self-styled "angel expert" (actually a dog trainer hired by Malt to eventually replace Driscoll).', 3.25, 5, 7)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Youve Got Mail', 'Nora Ephron', '1998-12-18', 'Kathleen Kelly (Meg Ryan) is involved with Frank Navasky (Greg Kinnear), a 
leftist postmodernist newspaper writer for the New York Observer whos always in search of an opportunity to root for the underdog. 
While Frank is devoted to his typewriter, Kathleen prefers her laptop and logging into her AOL e-mail account. There, using the screen 
name Shopgirl, she reads an e-mail from "NY152", the screen name of Joe Fox (Tom Hanks). In her reading of the e-mail, she reveals 
the boundaries of the online relationship; no specifics, including no names, career or class information, or family connections. Joe 
belongs to the Fox family which runs Fox Books — a chain of "mega" bookstores similar to Borders or Barnes & Noble.', 3.25, 5, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Bewitched', 'Nora Ephron', '2005-06-24', 'Jack Wyatt (Will Ferrell) is a narcissistic actor who is approached to play the role of 
Darrin in a remake of the classic sitcom Bewitched but insists that an unknown play Samantha.  Isabel Bigelow (Nicole Kidman) is an 
actual witch who decides she wants to be normal and moves to Los Angeles to start a new life and becomes friends with her neighbor 
Maria (Kristin Chenoweth). She goes to a bookstore to learn how to get a job after seeing an advertisement of Ed McMahon on TV.', 
4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Love Story', 'Arthur Hiller', '1970-12-16', 'The film tells of Oliver Barrett IV, who comes from a family of wealthy and 
well-respected Harvard University graduates. At Radcliffe library, the Harvard student meets and falls in love with Jennifer Cavalleri, 
a working-class, quick-witted Radcliffe College student. Upon graduation from college, the two decide to marry against the wishes of 
Olivers father, who thereupon severs ties with his son.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Godfather', 'Francis Ford Coppola', '1972-03-15', 'On the day of his only daughters wedding, Vito Corleone hears requests in 
his role as the Godfather, the Don of a New York crime family. Vitos youngest son, Michael, in Marine Corps khakis, introduces his 
girlfriend, Kay Adams, to his family at the sprawling reception. Vitos godson Johnny Fontane, a popular singer, pleads for help in 
securing a coveted movie role, so Vito dispatches his consigliere, Tom Hagen, to the abrasive studio head, Jack Woltz, to secure the 
casting. Woltz is unmoved until the morning he wakes up in bed with the severed head of his prized stallion.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Chinatown', 'Roman Polanski', '1974-06-20', 'A woman identifying herself as Evelyn Mulwray (Ladd) hires private investigator 
J.J. "Jake" Gittes (Nicholson) to perform matrimonial surveillance on her husband Hollis I. Mulwray (Zwerling), the chief engineer for 
the Los Angeles Department of Water and Power. Gittes tails him, hears him publicly oppose the creation of a new reservoir, and 
shoots photographs of him with a young woman (Palmer) that hit the front page of the following days paper. Upon his return to his 
office he is confronted by a beautiful woman who, after establishing that the two of them have never met, irately informs him that 
she is in fact Evelyn Mulwray (Dunaway) and he can expect a lawsuit.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Saint', 'Phillip Noyce', '1997-04-04', 'At the Saint Ignatius Orphanage, a rebellious boy named John Rossi refers to himself 
as "Simon Templar" and leads a group of fellow orphans as they attempt to run away to escape their harsh treatment. When Simon is 
caught by the head priest, he witnesses the tragic death of a girl he had taken a liking to when she accidentally falls from a balcony.', 
3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Alexander', 'Oliver Stone', '2004-11-24', 'The film is based on the life of Alexander the Great, King of Macedon, who conquered 
Asia Minor, Egypt, Persia and part of Ancient India. Shown are some of the key moments of Alexanders youth, his invasion of the 
mighty Persian Empire and his death. It also outlines his early life, including his difficult relationship with his father Philip II of 
Macedon, his strained feeling towards his mother Olympias, the unification of the Greek city-states and the two Greek Kingdoms 
(Macedon and Epirus) under the Hellenic League,[3] and the conquest of the Persian Empire in 331 BC. It also details his plans to 
reform his empire and the attempts he made to reach the end of the then known world.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Terminator Salvation', 'Joseph McGinty Nichol', '2009-05-21', 'In 2003, Doctor Serena Kogan (Helena Bonham Carter) of 
Cyberdyne Systems convinces death row inmate Marcus Wright (Sam Worthington) to sign his body over for medical research following 
his execution by lethal injection. One year later the Skynet system is activated, perceives humans as a threat to its own existence, 
and eradicates much of humanity in the event known as "Judgment Day" (as depicted in Terminator 3: Rise of the Machines).', 
4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('I Know What You Did Last Summer', 'Jim Gillespie', '1997-10-17', 'Four friends, Helen Shivers (Sarah Michelle Gellar), Julie 
James (Jennifer Love Hewitt), Barry Cox (Ryan Phillippe), and Ray Bronson (Freddie Prinze Jr.) go out of town to celebrate Helens 
winning the Miss Croaker pageant. Returning in Barrys new car, they hit and apparently kill a man, who is unknown to them. They 
dump the corpse in the ocean and agree to never discuss again what had happened.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Score', 'Frank Oz', '2001-07-13', 'After nearly being caught on a routine burglary, master safe-cracker Nick Wells (Robert De 
Niro) decides the time has finally come to retire. Nicks flight attendant girlfriend, Diane (Angela Bassett), encourages this decision, 
promising to fully commit to their relationship if he does indeed go straight. Nick, however, is lured into taking one final score by his 
fence Max (Marlon Brando) The job, worth a $4 million pay off to Nick, is to steal a valuable French sceptre, which was being smuggled 
illegally into the United States through Canada but was accidentally discovered and kept at the Montréal Customs House.', 4.75, 3, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Sleepy Hollow', 'Tim Burton', '1999-11-19', 'In 1799, New York City, Ichabod Crane is a 24-year-old police officer. He is dispatched 
by his superiors to the Westchester County hamlet of Sleepy Hollow, New York, to investigate a series of brutal slayings in which the 
victims have been found decapitated: Peter Van Garrett, wealthy farmer and landowner; his son Dirk; and the widow Emily Winship, 
who secretly wed Van Garrett and was pregnant before being murdered. A pioneer of new, unproven forensic techniques such as 
finger-printing and autopsies, Crane arrives in Sleepy Hollow armed with his bag of scientific tools only to be informed by the towns 
elders that the murderer is not of flesh and blood, rather a headless undead Hessian mercenary from the American Revolutionary War 
who rides at night on a massive black steed in search of his missing head.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('I Still Know What You Did Last Summer', 'Danny Cannon', '1998-11-13', 'Julie James is getting over the events of the previous 
film, which nearly claimed her life. She hasnt been doing well in school and is continuously having nightmares involving Ben Willis 
(Muse Watson) still haunting her. Approaching the 4th July weekend, Ray (Freddie Prinze, Jr.) surprises her at her dorm. He invites 
her back up to Southport for the Croaker queen pageant. She objects and tells him she has not healed enough to go back. He tells her 
she needs some space away from Southport and him and leaves in a rush. After getting inside,she sits on her bed and looks at a picture 
of her deceased best friend Helen (Sarah Michelle Gellar), who died the previous summer at the hands of the fisherman.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard with a Vengeance', 'John McTiernan', '1995-05-19', 'In New York City, a bomb detonates destroying the Bonwit Teller 
department store. A man calling himself "Simon" phones Major Case Unit Inspector Walter Cobb of the New York City Police 
Department, claiming responsibility for the bomb. He demands that suspended police officer Lt. John McClane be dropped in Harlem 
wearing a sandwich board that says "I hate Niggers". Harlem shop owner Zeus Carver spots McClane and tries to get him off the street 
before he is killed, but a gang of black youths attack the pair, who barely escape. Returning to the station, they learn that Simon is 
believed to have stolen several thousand gallons of an explosive compound. Simon calls again demanding McClane and Carver put 
themselves through a series of "games" to prevent more explosions.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Terminator 3: Rise of the Machines', 'Jonathan Mostow', '2003-07-02', 'For nine years, John Connor (Nick Stahl) has been living 
off-the-grid in Los Angeles. Although Judgment Day did not occur on August 29, 1997, John does not believe that the prophesied war 
between humans and Skynet has been averted. Unable to locate John, Skynet sends a new model of Terminator, the T-X (Kristanna 
Loken), back in time to July 24, 2004 to kill his future lieutenants in the human Resistance. A more advanced model than previous 
Terminators, the T-X has an endoskeleton with built-in weaponry, a liquid metal exterior similar to the T-1000, and the ability to 
control other machines. The Resistance sends a reprogrammed T-850 model 101 Terminator (Arnold Schwarzenegger) back in time to 
protect the T-Xs targets, including Kate Brewster (Claire Danes) and John.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Amityville Horror', 'Andrew Douglas', '2005-04-15', 'On November 13, 1974, at 3:15am, Ronald DeFeo, Jr. shot and killed his 
family at their home, 112 Ocean Avenue in Amityville, New York. He killed five members of his family in their beds, but his youngest 
sister, Jodie, had been killed in her bedroom closet. He claimed that he was persuaded to kill them by voices he had heard in the 
house.', 4.75, 3, 21)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Runaway Bride', 'Garry Marshall', '1999-07-30', 'Maggie Carpenter (Julia Roberts) is a spirited and attractive young woman who 
has had a number of unsuccessful relationships. Maggie, nervous of being married, has left a trail of fiances. It seems, shes left three 
men waiting for her at the altar on their wedding day (all of which are caught on tape), receiving tabloid fame and the dubious 
nickname "The Runaway Bride".', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Jumanji', 'Joe Johnston', '1995-12-15', 'In 1869, two boys bury a chest in a forest near Keene, New Hampshire. A century later, 
12-year-old Alan Parrish flees from a gang of bullies to a shoe factory owned by his father, Sam, where he meets his friend Carl Bentley, 
one of Sams employees. When Alan accidentally damages a machine with a prototype sneaker Carl hopes to present, Carl takes the 
blame and loses his job. Outside the factory, after the bullies beat Alan up and steal his bicycle, Alan follows the sound of tribal 
drumbeats to a construction site and finds the chest, containing a board game called Jumanji.', 3.25, 5, 24)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Revenge of the Nerds', 'Jeff Kanew', '1984-07-20', 'Best friends and nerds Lewis Skolnick (Robert Carradine) and Gilbert Lowe 
(Anthony Edwards) enroll in Adams College to study computer science. The Alpha Betas, a fraternity to which many members of the 
schools football team belong, carelessly burn down their own house and seize the freshmen dorm for themselves. The college allows 
the displaced freshmen, living in the gymnasium, to join fraternities or move to other housing. Lewis, Gilbert, and other outcasts who 
cannot join a fraternity renovate a dilapidated home to serve as their own fraternity house.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Easy Rider', 'Dennis Hopper', '1969-07-14', 'The protagonists are two freewheeling hippies: Wyatt (Fonda), nicknamed "Captain 
America", and Billy (Hopper). Fonda and Hopper said that these characters names refer to Wyatt Earp and Billy the Kid.[4] Wyatt 
dresses in American flag-adorned leather (with an Office of the Secretary of Defense Identification Badge affixed to it), while Billy 
dresses in Native American-style buckskin pants and shirts and a bushman hat. The former is appreciative of help and of others, while 
the latter is often hostile and leery of outsiders.', 3.25, 5, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Braveheart', 'Mel Gibson', '1995-05-24', 'In 1280, King Edward "Longshanks" (Patrick McGoohan) invades and conqueres Scotland 
following the death of Scotlands King Alexander III who left no heir to the throne. Young William Wallace witnesses the treachery of 
Longshanks, survives the death of his father and brother, and is taken abroad to Rome by his Uncle Argyle (Brian Cox) where he is 
educated.', 3.25, 5, 1)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Passion of the Christ', 'Mel Gibson', '2004-02-25', 'The film opens in Gethsemane as Jesus prays and is tempted by Satan, 
while his apostles, Peter, James and John sleep. After receiving thirty pieces of silver, one of Jesus other apostles, Judas, approaches 
with the temple guards and betrays Jesus with a kiss on the cheek. As the guards move in to arrest Jesus, Peter cuts off the ear of 
Malchus, but Jesus heals the ear. As the apostles flee, the temple guards arrest Jesus and beat him during the journey to the 
Sanhedrin. John tells Mary and Mary Magdalene of the arrest while Peter follows Jesus at a distance. Caiaphas holds trial over the 
objection of some of the other priests, who are expelled from the court.', 4.75, 3, 8)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Finding Neverland', 'Marc Forster', '2004-11-12', 'The story focuses on Scottish writer J. M. Barrie, his platonic relationship with 
Sylvia Llewelyn Davies, and his close friendship with her sons, who inspire the classic play Peter Pan, or The Boy Who Never Grew Up.', 
4.75, 3, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Bourne Identity', 'Doug Liman', '2002-06-14', 'In the Mediterranean Sea near Marseille, Italian fishermen rescue an 
unconscious man floating adrift with two gunshot wounds in his back. The boats medic finds a tiny laser projector surgically implanted 
under the unknown mans skin at the level of the hip. When activated, the laser projector displays the number of a safe deposit box in 
Zürich. The man wakes up and discovers he is suffering from extreme memory loss. Over the next few days on the ship, the man finds 
he is fluent in several languages and has unusual skills, but cannot remember anything about himself or why he was in the sea. When 
the ship docks, he sets off to investigate the safe deposit box.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Cider House Rules', 'Lasse Hallström', '1999-12-17', 'Homer Wells (Tobey Maguire), an orphan, is the films protagonist. He 
grew up in an orphanage directed by Dr. Wilbur Larch (Michael Caine) after being returned twice by foster parents. His first foster 
parents thought he was too quiet and the second parents beat him. Dr. Larch is addicted to ether and is also secretly an abortionist. 
Larch trains Homer in obstetrics and abortions as an apprentice, despite Homer never even having attended high school.', 3.25, 5, 9)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Field of Dreams', 'Phil Alden Robinson', '1989-04-21', 'While walking in his cornfield, novice farmer Ray Kinsella hears a voice 
that whispers, "If you build it, he will come", and sees a baseball diamond. His wife, Annie, is skeptical, but she allows him to plow 
under his corn to build the field.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Waterworld', 'Kevin Reynolds', '1995-07-28', 'In the future (year 2500), the polar ice caps have melted due to the global warming, 
and the sea level has risen hundreds of meters, covering every continent and turning Earth into a water planet. Human population 
has been scattered across the ocean in individual, isolated communities consisting of artificial islands and mostly decrepit sea vessels. 
It was so long since the events that the humans eventually forgot that there were continents in the first place and that there is a 
place on Earth called "the Dryland", a mythical place.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard', 'John McTiernan', '1988-07-15', 'New York City Police Department detective John McClane arrives in Los Angeles to 
reconcile with his estranged wife, Holly. Limo driver Argyle drives McClane to the Nakatomi Plaza building to meet Holly at a company 
Christmas party. While McClane changes clothes, the party is disrupted by the arrival of German terrorist Hans Gruber and his heavily 
armed group: Karl, Franco, Tony, Theo, Alexander, Marco, Kristoff, Eddie, Uli, Heinrich, Fritz and James. The group seizes the 
skyscraper and secure those inside as hostages, except for McClane, who manages to slip away, armed with only his service sidearm, a 
Beretta 92F pistol.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Die Hard 2', 'Renny Harlin', '1990-07-04', 'On Christmas Eve, two years after the Nakatomi Tower Incident, John McClane is 
waiting at Washington Dulles International Airport for his wife Holly to arrive from Los Angeles, California. Reporter Richard Thornburg, 
who exposed Hollys identity to Hans Gruber in Die Hard, is assigned a seat across the aisle from her. While in the airport bar, McClane 
spots two men in army fatigues carrying a package; one of the men has a gun. Suspicious, he follows them into the baggage area. After 
a shootout, he kills one of the men while the other escapes. Learning the dead man is a mercenary thought to have been killed in 
action, McClane believes hes stumbled onto a nefarious plot. He relates his suspicions to airport police Captain Carmine Lorenzo, but 
Lorenzo refuses to listen and has McClane thrown out of his office.', 3.25, 5, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Splash', 'Ron Howard', '1984-03-09', 'As an eight year-old boy, Allen Bauer (David Kreps) is vacationing with his family near Cape 
Cod. While taking a sight-seeing tour on a ferry, he gazes into the ocean and sees something below the surface that fascinates him. 
Allen jumps into the water, even though he cannot swim. He grasps the hands of a girl who is inexplicably under the water with him 
and an instant connection forms between the two. Allen is quickly pulled to the surface by the deck hands and the two are separated, 
though apparently no one else sees the girl. After the ferry moves off, Allen continues to look back at the girl in the water, who cries 
at their separation.', 3.25, 5, 25)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Parenthood', 'Ron Howard', '1989-08-02', 'Gil Buckman (Martin), a neurotic sales executive, is trying to balance his family and 
his career in suburban St. Louis. When he finds out that his eldest son, Kevin, has emotional problems and needs therapy, and that his 
two younger children, daughter Taylor and youngest son Justin, both have issues as well, he begins to blame himself and questions his 
abilities as a father. When his wife, Karen (Steenburgen), becomes pregnant with their fourth child, he is unsure he can handle it.', 
3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Apollo 13', 'Ron Howard', '1995-06-30', 'On July 20, 1969, veteran astronaut Jim Lovell (Tom Hanks) hosts a party for other 
astronauts and their families, who watch on television as their colleague Neil Armstrong takes his first steps on the Moon during the 
Apollo 11 mission. Lovell, who orbited the Moon on Apollo 8, tells his wife Marilyn (Kathleen Quinlan) that he intends to return, to 
walk on its surface.', 3.25, 5, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Dr. Seuss How the Grinch Stole Christmas', 'Ron Howard', '2000-11-17', 'In the microscopic city of Whoville, everyone celebrates 
Christmas with much happiness and joy, with the exception of the cynical and misanthropic Grinch (Jim Carrey), who despises 
Christmas and the Whos with great wrath and occasionally pulls dangerous and harmful practical jokes on them. As a result, no one 
likes or cares for him.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('A Beautiful Mind', 'Ron Howard', '2001-12-21', 'In 1947, John Nash (Russell Crowe) arrives at Princeton University. He is co-recipient, 
with Martin Hansen (Josh Lucas), of the prestigious Carnegie Scholarship for mathematics. At a reception he meets a group of other 
promising math and science graduate students, Richard Sol (Adam Goldberg), Ainsley (Jason Gray-Stanford), and Bender (Anthony Rapp). 
He also meets his roommate Charles Herman (Paul Bettany), a literature student, and an unlikely friendship begins.', 4.75, 3, 5)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Da Vinci Code', 'Ron Howard', '2006-05-19', 'In Paris, Jacques Saunière is pursued through the Louvres Grand Gallery by 
albino monk Silas (Paul Bettany), demanding the Priorys clef de voûte or "keystone." Saunière confesses the keystone is kept in the 
sacristy of Church of Saint-Sulpice "beneath the Rose" before Silas shoots him. At the American University of Paris, Robert Langdon, a 
symbologist who is a guest lecturer on symbols and the sacred feminine, is summoned to the Louvre to view the crime scene. He 
discovers the dying Saunière has created an intricate display using black light ink and his own body and blood. Captain Bezu Fache 
(Jean Reno) asks him for his interpretation of the puzzling scene.', 4.75, 3, 3)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('The Simpsons Movie', 'David Silverman', '2007-07-27', 'While performing on Lake Springfield, rock band Green Day are killed 
when pollution in the lake dissolves their barge, following an audience revolt after frontman Billie Joe Armstrong proposes an 
environmental discussion. At a memorial service, Grampa has a prophetic vision in which he predicts the impending doom of the town, 
but only Marge takes it seriously. Then Homer dares Bart to skate naked and he does so. Lisa and an Irish boy named Colin, with whom 
she has fallen in love, hold a meeting where they convince the town to clean up the lake.', 4.75, 3, 6)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Crash', 'Paul Haggis', '2005-05-06', 'Los Angeles detectives Graham Waters (Don Cheadle) and his partner Ria (Jennifer Esposito) 
approach a crime scene investigation. Waters exits the car to check out the scene. One day prior, Farhad (Shaun Toub), a Persian 
shop owner, and his daughter, Dorri (Bahar Soomekh), argue with each other in front of a gun store owner as Farhad tries to buy a 
revolver. The shop keeper grows impatient and orders an infuriated Farhad outside. Dorri defiantly finishes the gun purchase, which 
she had opposed. The purchase entitles the buyer to one box of ammunition. She selects a red box.', 4.75, 3, 20)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Million Dollar Baby', 'Clint Eastwood', '2004-12-15', 'Margaret "Maggie" Fitzgerald, a waitress from a Missouri town in the Ozarks, 
shows up in the Hit Pit, a run-down Los Angeles gym which is owned and operated by Frankie Dunn, a brilliant but only marginally 
successful boxing trainer. Maggie asks Dunn to train her, but he angrily responds that he "doesnt train girls."', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Letters from Iwo Jima', 'Clint Eastwood', '2006-12-20', 'In 2005, Japanese archaeologists explore tunnels on Iwo Jima, where they 
find something buried in the soil.  The film flashes back to Iwo Jima in 1944. Private First Class Saigo is grudgingly digging trenches on 
the beach. A teenage baker, Saigo has been conscripted into the Imperial Japanese Army despite his youth and his wifes pregnancy. 
Saigo complains to his friend Private Kashiwara that they should let the Americans have Iwo Jima. Overhearing them, an enraged 
Captain Tanida starts brutally beating them for "conspiring with unpatriotic words." At the same time, General Tadamichi Kuribayashi 
arrives to take command of the garrison and immediately begins an inspection of the island defenses.', 4.75, 3, 10)
insert into Video(Video_Title, Video_Director, Video_ReleaseDate, Video_Description, Video_Cost, Video_RentalDays, Distributor_ID)
values ('Cast Away', 'Robert Zemeckis', '2000-12-07', 'In 1995, Chuck Noland (Tom Hanks) is a time-obsessed systems analyst, who travels 
worldwide resolving productivity problems at FedEx depots. He is in a long-term relationship with Kelly Frears (Helen Hunt), whom he 
lives with in Memphis, Tennessee. Although the couple wants to get married, Chucks busy schedule interferes with their relationship. 
A Christmas with relatives is interrupted by Chuck being summoned to resolve a problem in Malaysia.', 4.75, 3, 6)

--Stored Procedure for inserting Distributors--
Create procedure "SP_LoadDirectors"
as
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Paramount Pictures', '5555 Melrose Ave', 'Los Angeles', 'CA', '90038', '323', '9568398', 'Adolph Zukor')    
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Compass International Pictures', '2021 Pontius Avenue', 'Los Angeles', 'CA', '90025', '310', '4776569', 'Irwin Yablans')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Columbia Pictures', '10202 Washington Blvd.', 'Culver City', 'CA', '90232', '310', '2444000', 'Harry Cohn')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('DreamWorks Pictures', '100 Universal City Plaza, Bldg. 10', 'Universal City' , 'CA', '91608', '818', '7337000', 'Steven Spielberg')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Universal Pictures', '100 Universal City Plaza', 'Universal City', 'CA', '91608', '818', '7771000', 'Carl Laemmle')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('20th Century Fox', '10201 W. Pico Blvd.', 'Los Angeles', 'CA', '90064', '310', '3691000', 'William Fox')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('New Line Cinema', '116 N. Robertson Blvd., Ste. 200', 'Los Angeles', 'CA', '90048', '310', '8545811', 'Michael Lynne')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Newmarket Films', '202 N. Cannon Dr.', 'Beverly Hills', 'CA', '90210', '310', '8587472', 'William Tyrer')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Miramax Films', '1601 Cloverfield Blvd.', 'Santa Monica', 'CA', '90404', '310', '4094321', 'Harvey Weinstein')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Warner Bros. Pictures', '4000 Warner Boulevard', 'Burbank', 'CA', '91522', '818', '9541744', 'Jack Warner')		
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Paramount Vantage', '555 Melrose Ave., Chevalier Bldg., 2nd Fl.', 'Los Angeles', 'CA', '90038', '323', '9565000', 'Adolph Zukor')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('United Artists', '10250 Constellation Blvd.', 'Los Angeles', 'CA', '90067', '310', '4493000', 'Douglas Fairbanks')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Hollywood Pictures', '500 S. Buena Vista St.', 'Burbank', 'CA', '91521', '818', '5601000', 'Michael Eisner')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Touchstone Pictures', '500 S Buena Vista St.', 'Burbank', 'CA', '91527', '818', '5601000', 'Michael Eisner')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Walt Disney Pictures', '500 S Buena Vista St.', 'Burbank', 'CA', '91527', '818', '5601000', 'Walt Disney')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Focus Features', '65 Bleecker St., 3rd Fl.', 'New York', 'NY', '10012', '212', '5394000', 'David Linde')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Sony Pictures', '10202 W Washington Blvd', 'Culver City', 'CA', '90232', '310', '2444000', 'Jack Cohn')	
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('USA Films', '2021 North Western Avenue', 'Los Angeles', 'CA', '90027', '323', '8567600', 'Bob Gazzale')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Gramercy Pictures', '825 8th Ave.', 'New York', 'NY', '10019', '212', '3338000', 'Barry Diller')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Lionsgate', '2700 Colorado Ave., Ste. 200', 'Santa Monica', 'CA', '90404', '310', '4499200', 'Frank Giustra')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values 
('Warner Independent Pictures', '4000 Warner Blvd.', 'Burbank', 'CA', '91522', '818', '9546000', 'Polly Cohen')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values
('Dimension Films', '375 Greenwich Street', 'New York', 'NY', '10013', '212', '9413800', 'Bob Weinstein')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values
('TriStar Pictures', '10202 W. Washington Blvd.', 'Culver City', 'CA', '90232', '310', '2444000', 'Steve McQuinn')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values
('Buena Vista Distribution Company', '500 S. Buena Vista St.', 'Burbank', 'CA', '91521', '818', '5605670', 'Walt Disney')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values
('IFC Films', '11 Penn Plaza 15th Floor', 'New York', 'NY', '10001', '646', '2737200', 'Jonathan Sehring')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values
('Fox Searchlight Pictures', '10201 W. Pico Blvd., Bldg. 769', 'Los Angeles', 'CA', '90035', '310', '3694402', 'Stephen Gilula')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values
('Fine Line Features', '888 7th Avenue', 'New York', 'NY', '10106', '212', '6494800', 'Ira Deutchman')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values
('Turner Entertainment', '190 Marietta St. NW', 'Atlanta', 'GA', '30303', '404', '8271700', 'Ted Turner')
insert into Distributor(Distributor_Name, Distributor_Address, Distributor_City, Distributor_State, 
Distributor_ZipCode, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson) values
('Metro-Goldwyn-Mayer', '245 N Beverly Dr.', 'Beverly Hills', 'CA', '90210', '310', '4493000', 'Marcus Loew')

--Stored Procedure for Renting Video--
create procedure "SP_RentVideo"
@Member_ID int, @Video_ID int
as
declare @Video_Availability varchar(15) 
select @Video_Availability = Video_Availability from Video
where Video_ID = @Video_ID
if @Video_Availability = 'Unavailable'
begin
print 'This video has already been rented, please choose another'
end
if @Video_Availability = 'Damaged'
begin
print 'This video is damaged and unavailable for rent, please choose another'
end
else
insert into [Transaction](Member_ID, Video_ID, Transaction_Type, Transaction_Date) values (@Member_ID, @Video_ID, 'Rent', 
getdate())

--Stored procedure for Returning Video--
create procedure "SP_ReturnVideo"
@Member_ID int, @Video_ID int
as
insert into [Transaction](Member_ID, Video_ID, Transaction_Type, Transaction_Date) values (@Member_ID, @Video_ID, 'Return', 
getdate())

--Stored procedure RentProcess
create procedure "SP_RentProcess"
@Video_ID int, @Transaction_ID int, @Transaction_Date datetime
as
select @Video_ID = V.Video_ID, @Transaction_ID = T.Transaction_ID, 
@Transaction_Date = T.Transaction_Date
from Video V
join TransactionLineItems TL
on V.Video_ID = TL.Video_ID
join [Transaction] T
on TL.Transaction_ID = T.Transaction_ID
where V.Video_ID = @Video_ID
group by T.Member_ID, V.Video_ID, T.Transaction_ID, T.Transaction_Date, V.Video_Cost
insert into TransactionLineItems(Video_ID, Transaction_ID, RentalDate) values
(@Video_ID, @Transaction_ID, @Transaction_Date)

--Stored procedure ReturnProcess--
create procedure "SP_ReturnProcess"
@Member_ID int, @Video_ID int, @Transaction_ID int, @Transaction_Date datetime, @Video_DateDue datetime
as
select @Video_ID = V.Video_ID, @Transaction_ID = T.Transaction_ID, @Transaction_Date = T.Transaction_Date, 
@Member_ID = T.Member_ID, @Video_DateDue = V.Video_DateDue
from Video V
join ReturnVideo R
on V.Video_ID = R.Video_ID
join [Transaction] T
on R.Transaction_ID = T.Transaction_ID
where V.Video_ID = @Video_ID 
insert into ReturnVideo(Transaction_ID, Member_ID, Video_ID, Return_Date, Return_DaysLate, ChargePerDay, Return_LateCharge) values
(@Transaction_ID, @Member_ID, @Video_ID, @Transaction_Date, dbo.CalcDaysLate(@Video_ID), 1.50, 
dbo.CalcDaysLate(@Video_ID) * 1.50)

--Stored Procedure for adding Member--
create procedure "SP_AddMember"
@Member_FName varchar(20), @Member_MInitial varchar(1), @Member_LName varchar(20), @Member_Address varchar(30), 
@Member_City varchar(15), @Member_State varchar(2), @Member_ZipCode nvarchar(6),
@Member_Email varchar(40), @Member_AreaCode nvarchar(3), @Member_Phone nvarchar(7)
as
insert into Member(Member_FName, Member_MInitial, Member_LName, Member_Address, Member_City, Member_State, Member_ZipCode,
Member_Email, Member_AreaCode, Member_Phone, Member_StartDate) values (@Member_FName, @Member_MInitial, @Member_LName, @Member_Address, 
@Member_City, @Member_State, @Member_ZipCode, @Member_Email, @Member_AreaCode, @Member_Phone, getdate())

--Stored Procedure for Damaged Video--
create procedure "SP_DamagedVideo"
@Video_ID int, @DamageDescription varchar(100)
as
select @Video_ID = V.Video_ID
from Video V
join DamagedVideo D
on V.Video_ID = D.Video_ID
where V.Video_ID = @Video_ID
insert into DamagedVideo(Video_ID, DamageDescription) values (@Video_ID, @DamageDescription) 
