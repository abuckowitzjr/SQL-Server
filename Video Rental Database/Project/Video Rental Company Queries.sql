--Problem 1--
select Video_ID, Video_Title, Video_ReleaseDate, Video_Description
from Video
order by Video_ReleaseDate asc, Video_Title asc

--Problem 2--
select Video_ID, Video_Title, Video_ReleaseDate, Video_Description
from Video
where Video_Title = 'The Godfather'
order by Video_ReleaseDate asc, Video_Title asc

--Problem 3--
select Distributor_ID, Distributor_Name, Distributor_Address, Distributor_AreaCode, Distributor_Phone, Distributor_ContactPerson
from Distributor
order by Distributor_Name

--Problem 4--
select Member_ID, Member_Fname, Member_MInitial, Member_LName, Member_AreaCode, Member_Phone
from Member
order by Member_AreaCode

--Problem 5--
select * from Video
where Video_Availability = 'Unavailable'

--Problem 6--
select Video_DateDue, M.Member_AreaCode, M.Member_Phone, M.Member_FName, M.Member_MInitial, M.Member_LName
from Video V
left join TransactionLineItems TL
on V.Video_ID = TL.Video_ID
left join [Transaction] T
on TL.Transaction_ID = T.Transaction_ID
left join Member M
on T.Member_ID = M.Member_ID
where dbo.CalcDaysLate(V.Video_ID) > 0
order by V.Video_DateDue asc, M.Member_AreaCode asc, M.Member_FName

--Problem 7--
select Video.Video_Title, count(V.Video_Title) as Quantity
from Video
left join Video V
on Video.Video_ID = V.Video_ID
group by Video.Video_Title, V.Video_Availability
having count(V.Video_Availability) < 3 and V.Video_Availability = 'Available'

--Problem 8--
select V.Video_ID, V.Video_Title, isnull(D.DamageDescription, 'Rented') as Reason
from Video V
left join DamagedVideo D
on V.Video_ID = D.Video_ID
where V.Video_Availability = 'Unavailable' or V.Video_Availability = 'Damaged'

--Problem 9--
select Member_ID, Member_FName, Member_MInitial, Member_LName, Member_StartDate
from Member
where datediff(year, Member_StartDate, getdate()) >= 2

--Problem 10--
select top 1 datename(month, Member_StartDate) as "Month"
from Member
group by datename(month, Member_StartDate)
order by count(datepart(month, Member_StartDate)) desc


