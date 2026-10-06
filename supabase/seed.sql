-- Synthetic empty workshop. No real customers, passwords, or users.
insert into private.workshops(id,name,billing_country)
values('a110fc00-0000-4000-8000-000000000001','Taller de demostración','ES') on conflict do nothing;
insert into private.catalog(workshop_id,id,reference,description,unit,price_cents,cost_cents,stock_milli,min_milli) values
('a110fc00-0000-4000-8000-000000000001','a110fc00-0000-4000-8000-000000000011','OIL-5W30','Aceite 5W-30','L',1450,650,48000,15000),
('a110fc00-0000-4000-8000-000000000001','a110fc00-0000-4000-8000-000000000012','FLT-OL-01','Filtro de aceite','ud',1800,900,6000,2000)
on conflict do nothing;
