
/* =====================================================================================
   32. SEED - SUPPLIERS, PROPERTIES, FIXED ASSETS, INSURANCE, LEASES, LOAN,
       OPENING BALANCES (31 December 2024 - the ERP went live on 1 January 2025)
   ===================================================================================== */

-- 32.1 Suppliers --------------------------------------------------------------------------
INSERT INTO vendors (vendor_code, name, vendor_type, tax_number, vat_number, is_resident, tax_clearance_expiry, praz_registered,
                     email, phone, country_code, currency_code, payment_terms_days, bank_name, bank_account_number, default_expense_account_id)
SELECT v.code, v.name, v.t, v.tin, v.vat, v.res, v.itf::DATE, v.praz, v.email, v.phone, v.cc, v.cur, v.terms, v.bank, v.acc,
       CASE WHEN v.gl IS NOT NULL THEN fn_account_id(v.gl) END
  FROM (VALUES
   ('V001','ZESA Holdings - ZETDC','utility','2000100001','220100001',TRUE,NULL,FALSE,'accounts@zetdc.co.zw','+263 242 774 508','ZW','USD',14,'CBZ Bank','0100200300','6110'),
   ('V002','City of Harare','government','2000100002',NULL,TRUE,NULL,FALSE,'revenue@hararecity.co.zw','+263 242 752 577','ZW','USD',30,'CBZ Bank','0100200301','6110'),
   ('V003','City of Bulawayo','government','2000100003',NULL,TRUE,NULL,FALSE,'revenue@citybyo.co.zw','+263 292 75011','ZW','USD',30,'CABS','0100200302','6110'),
   ('V004','Zimlink Fibre (Pvt) Ltd','supplier','2000100004','220100004',TRUE,'2026-12-31',TRUE,'billing@zimlink.co.zw','+263 242 555 100','ZW','USD',30,'Stanbic Bank','9140000004','6500'),
   ('V005','Mobicel Zimbabwe (Pvt) Ltd','supplier','2000100005','220100005',TRUE,'2026-12-31',TRUE,'corporate@mobicel.co.zw','+263 77 200 2000','ZW','USD',30,'Stanbic Bank','9140000005','6500'),
   ('V006','Microsoft Ireland Operations Ltd','supplier','IE8256796U',NULL,FALSE,NULL,FALSE,'billing@microsoft.com','+353 1 706 3117','GB','USD',30,'Citibank','IE00CITI0001','6200'),
   ('V007','Amazon Web Services EMEA SARL','supplier','LU26888617',NULL,FALSE,NULL,FALSE,'aws-receivables@amazon.com','+352 2789 0057','GB','USD',30,'Citibank','LU00CITI0002','6210'),
   ('V008','Relativity ODA LLC','supplier','US36-4430178',NULL,FALSE,NULL,FALSE,'ar@relativity.com','+1 312 263 1177','US','USD',30,'JPMorgan','US00JPM0003','6200'),
   ('V009','Guardline Security Services (Pvt) Ltd','supplier','2000100009','220100009',TRUE,'2026-11-30',TRUE,'accounts@guardline.co.zw','+263 242 480 900','ZW','USD',30,'CBZ Bank','0100200309','6130'),
   ('V010','Sparkle Cleaning Services','supplier','2000100010',NULL,TRUE,'2025-06-30',FALSE,'sparkleclean@gmail.com','+263 77 410 1010','ZW','USD',30,'CABS','1000200310','6130'),
   ('V011','Harare General Insurance Ltd','insurer','2000100011','220100011',TRUE,'2026-12-31',TRUE,'corporate@hgi.co.zw','+263 242 700 800','ZW','USD',30,'CBZ Bank','0100200311','6140'),
   ('V012','Chartered Assurance Partners','professional','2000100012','220100012',TRUE,'2026-12-31',TRUE,'billing@capartners.co.zw','+263 242 303 700','ZW','USD',30,'Stanbic Bank','9140000012','6700'),
   ('V013','Mhlanga & Associates Legal Practitioners','professional','2000100013','220100013',TRUE,'2026-12-31',FALSE,'accounts@mhlangalaw.co.zw','+263 242 250 600','ZW','USD',30,'CBZ Bank','0100200313','6700'),
   ('V014','Brand Africa Media (Pvt) Ltd','supplier','2000100014','220100014',TRUE,'2026-09-30',TRUE,'finance@brandafrica.co.zw','+263 242 870 400','ZW','USD',30,'Stanbic Bank','9140000014','6400'),
   ('V015','Zambezi Travel & Tours','supplier','2000100015','220100015',TRUE,'2026-12-31',TRUE,'corporate@zambezitravel.co.zw','+263 242 704 200','ZW','USD',14,'CBZ Bank','0100200315','5300'),
   ('V016','Sibanda Forensic Accountants','subcontractor','2000100016',NULL,TRUE,NULL,FALSE,'sibandafa@outlook.com','+263 77 316 1616','ZW','USD',30,'CABS','1000200316','5200'),
   ('V017','DataPlus Analytics (Pty) Ltd','subcontractor','ZA9012345678',NULL,FALSE,NULL,FALSE,'accounts@dataplus.co.za','+27 11 450 1700','ZA','USD',30,'FNB','62000017','5200'),
   ('V018','Zuva Energy (Pvt) Ltd','supplier','2000100018','220100018',TRUE,'2026-12-31',TRUE,'fleet@zuvaenergy.co.zw','+263 242 790 180','ZW','USD',14,'CBZ Bank','0100200318','6800'),
   ('V019','Harare Motor Services','supplier','2000100019','220100019',TRUE,'2026-10-31',TRUE,'service@hms.co.zw','+263 242 486 190','ZW','USD',30,'CBZ Bank','0100200319','6800'),
   ('V020','Paperlink Office Supplies','supplier','2000100020','220100020',TRUE,'2026-12-31',TRUE,'orders@paperlink.co.zw','+263 242 771 200','ZW','USD',30,'Stanbic Bank','9140000020','6900'),
   ('V021','Institute of Chartered Accountants of Zimbabwe','professional','2000100021',NULL,TRUE,'2026-12-31',FALSE,'members@icaz.org.zw','+263 242 301 100','ZW','USD',30,'CBZ Bank','0100200321','6300'),
   ('V022','Association of Certified Fraud Examiners','supplier','US58-1624890',NULL,FALSE,NULL,FALSE,'memberservices@acfe.com','+1 512 478 9000','US','USD',30,'Frost Bank','US00FROST22','6300'),
   ('V023','Axis Computers Zimbabwe (Pvt) Ltd','supplier','2000100023','220100023',TRUE,'2026-12-31',TRUE,'sales@axiscomputers.co.zw','+263 242 336 230','ZW','USD',30,'Stanbic Bank','9140000023','1530'),
   ('V024','Zimbabwe Motor Distributors','supplier','2000100024','220100024',TRUE,'2026-12-31',TRUE,'fleet@zmd.co.zw','+263 242 621 240','ZW','USD',30,'CBZ Bank','0100200324','1520'),
   ('V025','Delta Office Furniture','supplier','2000100025','220100025',TRUE,'2026-12-31',TRUE,'sales@deltafurniture.co.zw','+263 242 667 250','ZW','USD',30,'CBZ Bank','0100200325','1540'),
   ('V026','Magnet Forensics Inc.','supplier','CA81234 5678',NULL,FALSE,NULL,FALSE,'ar@magnetforensics.com','+1 844 638 7884','US','USD',30,'RBC','CA00RBC26','1800'),
   ('V027','Sandton Central Properties (Pty) Ltd','landlord','ZA4270100027','4270100027',TRUE,NULL,FALSE,'leasing@sandtoncentral.co.za','+27 11 300 2700','ZA','ZAR',7,'Standard Bank','00270100027',NULL),
   ('V028','Westlands Square Ltd','landlord','P051100028Z','0110028X',TRUE,NULL,FALSE,'accounts@westlandssquare.co.ke','+254 20 280 2800','KE','KES',7,'KCB','1100280028',NULL),
   ('V029','Minster Court Estates Ltd','landlord','GB290029029','GB290029029',TRUE,NULL,FALSE,'rent@minstercourt.co.uk','+44 20 7290 2900','GB','GBP',7,'HSBC','40-29-00 29002900',NULL),
   ('V030','DIFC Investments LLC','landlord','100300030000003','100300030000003',TRUE,NULL,FALSE,'leasing@difcinvest.ae','+971 4 362 2222','AE','AED',7,'Emirates NBD','1030030030',NULL),
   ('V031','Arundel Office Park (Pvt) Ltd','landlord','2000100031','220100031',TRUE,'2026-12-31',FALSE,'rentals@arundelpark.co.zw','+263 242 339 310','ZW','USD',7,'CBZ Bank','0100200331',NULL),
   ('V032','Sandton Office Services (Pty) Ltd','supplier','ZA4270100032','4270100032',TRUE,NULL,FALSE,'billing@sos.co.za','+27 11 300 3200','ZA','ZAR',30,'FNB','62000032','6110'),
   ('V033','Westlands Business Services','supplier','P051100033Z','0110033X',TRUE,NULL,FALSE,'billing@wbs.co.ke','+254 20 280 3300','KE','KES',30,'NCBA Bank','1100330033','6110'),
   ('V034','City Facilities Management Ltd','supplier','GB290029034','GB290029034',TRUE,NULL,FALSE,'ar@cityfm.co.uk','+44 20 7290 3400','GB','GBP',30,'Barclays','20-45-77 34003400','6110'),
   ('V035','Gulf Facilities Management LLC','supplier','100300030000035','100300030000035',TRUE,NULL,FALSE,'billing@gulffm.ae','+971 4 362 3500','AE','AED',30,'Emirates NBD','1030030035','6110'),
   ('V036','Zimbabwe Revenue Authority (ZIMRA)','government','ZIMRA',NULL,TRUE,NULL,FALSE,'lco@zimra.co.zw','+263 242 758 891','ZW','USD',0,'RBZ','ZIMRA-USD',NULL),
   ('V037','National Social Security Authority (NSSA)','government','NSSA',NULL,TRUE,NULL,FALSE,'contributions@nssa.org.zw','+263 242 706 523','ZW','USD',0,'CBZ Bank','NSSA-USD',NULL),
   ('V038','Zimbabwe Manpower Development Fund (ZIMDEF)','government','ZIMDEF',NULL,TRUE,NULL,FALSE,'levies@zimdef.org.zw','+263 242 790 912','ZW','USD',0,'CBZ Bank','ZIMDEF-USD',NULL),
   ('V039','Borrowdale Conference Centre (Pvt) Ltd','landlord','2000100039','220100039',TRUE,'2026-12-31',FALSE,'bookings@borrowdalecc.co.zw','+263 242 870 390','ZW','USD',7,'Stanbic Bank','9140000039',NULL),
   ('V040','Bulawayo Storage Solutions','landlord','2000100040','220100040',TRUE,'2026-12-31',FALSE,'info@byostorage.co.zw','+263 292 880 400','ZW','USD',7,'CABS','1000200340',NULL),
   ('V041','Maxhub Staff Pension Fund','professional','2000100041',NULL,TRUE,'2026-12-31',FALSE,'trustees@maxhubpension.co.zw','+263 242 700 141','ZW','USD',7,'CBZ Bank','0100200341',NULL),
   ('V042','CIMAS Medical Aid Society','professional','2000100042',NULL,TRUE,'2026-12-31',FALSE,'corporate@cimas.co.zw','+263 242 773 000','ZW','USD',7,'CBZ Bank','0100200342',NULL),
   ('V043','Cummins Power Zimbabwe','supplier','2000100043','220100043',TRUE,'2026-12-31',TRUE,'service@cumminszw.co.zw','+263 242 486 430','ZW','USD',30,'Stanbic Bank','9140000043','6120'),
   ('V044','SolarTech Africa (Pvt) Ltd','supplier','2000100044','220100044',TRUE,'2026-12-31',TRUE,'projects@solartech.co.zw','+263 242 870 440','ZW','USD',30,'CBZ Bank','0100200344','1550')
  ) AS v(code, name, t, tin, vat, res, itf, praz, email, phone, cc, cur, terms, bank, acc, gl);

UPDATE tax_authorities a SET vendor_id = v.vendor_id FROM vendors v
 WHERE (a.authority_code, v.vendor_code) IN (('ZIMRA','V036'), ('NSSA','V037'), ('ZIMDEF','V038'));

INSERT INTO tax_clearance_certificates (holder_type, vendor_id, certificate_no, issue_date, expiry_date)
VALUES ('company', NULL, 'ITF263-2026-0451236', '2026-01-05', '2026-12-31');
INSERT INTO tax_clearance_certificates (holder_type, vendor_id, certificate_no, issue_date, expiry_date)
SELECT 'vendor', vendor_id, 'ITF263-' || right(tax_number, 6), make_date(extract(year FROM tax_clearance_expiry)::INT, 1, 5), tax_clearance_expiry
  FROM vendors WHERE tax_clearance_expiry IS NOT NULL;

INSERT INTO tax_registrations (authority_code, office_id, registration_type, registration_no, registered_on, tax_office)
SELECT v.a, (SELECT office_id FROM offices WHERE code = v.o), v.t, v.n, v.d::DATE, v.office
  FROM (VALUES ('ZIMRA','HRE','TIN / BP number','2000451236','2012-06-15','ZIMRA Large Client Office, Harare'),
               ('ZIMRA','HRE','VAT (Category C)','220451236','2012-08-01','ZIMRA Large Client Office, Harare'),
               ('ZIMRA','HRE','PAYE employer','2000451236-PAYE','2012-06-15','ZIMRA Large Client Office, Harare'),
               ('NSSA','HRE','Employer registration','NSSA-EMP-0045123','2012-06-20','NSSA Harare'),
               ('ZIMDEF','HRE','Levy registration','ZDF-11873','2012-07-01','ZIMDEF Harare'),
               ('SARS','JNB','Income tax (external company)','9451236181','2018-07-15','SARS Large Business Centre'),
               ('SARS','JNB','VAT vendor','4451236181','2018-08-01','SARS'),
               ('KRA','NBO','PIN','P052451236M','2021-03-10','KRA Westlands'),
               ('HMRC','LON','Corporation tax UTR','45123 61234','2023-01-20','HMRC'),
               ('HMRC','LON','PAYE reference','120/MA45123','2023-01-20','HMRC'),
               ('UAEFTA','DXB','Tax registration number (TRN)','100451236100003','2024-03-01','Federal Tax Authority')) AS v(a, o, t, n, d, office);

-- 32.2 Properties & insurance -------------------------------------------------------------
INSERT INTO properties (property_code, name, address, city, country_code, stand_number, title_deed_number, land_size_sqm,
                        building_size_sqm, use_type, lettable_area_sqm, office_id, council, notes)
VALUES ('PRP-HRE-01','Maxhub House','45 Enterprise Road, Highlands','Harare','ZW','Stand 4412 Highlands Township','DT 2014/3321',4200,6800,'mixed',2040,
        (SELECT office_id FROM offices WHERE code='HRE'),'City of Harare','6 floors. Floors 1-4 owner-occupied (IAS 16). Floors 5-6 (30%) let to tenants - investment property (IAS 40).'),
       ('PRP-BYO-01','Maxhub Centre','88 Jason Moyo Street','Bulawayo','ZW','Stand 1180 Bulawayo Township','DT 2015/0877',1500,1900,'owner_occupied',NULL,
        (SELECT office_id FROM offices WHERE code='BYO'),'City of Bulawayo','Owner-occupied regional office.'),
       ('PRP-HRE-02','Mount Pleasant Business Park - Stand 22','Stand 22, Mount Pleasant Business Park','Harare','ZW','Stand 22 MPBP','DT 2022/1954',8000,NULL,'vacant_land',NULL,
        (SELECT office_id FROM offices WHERE code='HRE'),'City of Harare','Held for the future Maxhub campus (owner-occupation intended - IAS 16 land).');

INSERT INTO insurance_policies (policy_number, insurer_vendor_id, cover_type, sum_insured, annual_premium, start_date, end_date, excess_amount, notes)
SELECT v.no, (SELECT vendor_id FROM vendors WHERE vendor_code='V011'), v.cover, v.sum, v.prem, '2026-01-01', '2026-12-31', v.xs, v.notes
  FROM (VALUES ('HGI-PROP-2026-114','Property - buildings & contents (fire & allied perils)', 7500000, 21500, 5000, 'Maxhub House, Maxhub Centre'),
               ('HGI-MOT-2026-115','Motor fleet - comprehensive', 1100000, 41000, 1000, 'All company vehicles'),
               ('HGI-PI-2026-116','Professional indemnity', 5000000, 64000, 25000, 'Forensic & advisory engagements, worldwide excl. USA'),
               ('HGI-CYB-2026-117','Cyber liability', 2000000, 18500, 10000, 'Data breach, business interruption, ransomware'),
               ('HGI-EEI-2026-118','Electronic equipment (all risks)', 1400000, 9800, 250, 'Laptops, servers, forensic lab equipment')) AS v(no, cover, sum, prem, xs, notes);

-- 32.3 Asset categories (accounting policies) ----------------------------------------------
INSERT INTO asset_categories (code, name, asset_class, standard, measurement_model, depreciation_method, useful_life_months,
                              residual_value_pct, cost_account_id, acc_dep_account_id, dep_expense_account_id, reval_reserve_account_id,
                              tax_wear_tear_rate_pct, capitalisation_threshold)
SELECT v.code, v.name, v.cls, v.std, v.model, v.meth, v.life, v.resid, fn_account_id(v.cost),
       CASE WHEN v.ad IS NOT NULL THEN fn_account_id(v.ad) END, CASE WHEN v.dep IS NOT NULL THEN fn_account_id(v.dep) END,
       CASE WHEN v.res IS NOT NULL THEN fn_account_id(v.res) END, v.wt, v.thr
  FROM (VALUES
   ('LND','Land (revaluation model)','land','IAS 16','revaluation','none',NULL,0,'1500',NULL,NULL,'3300',0,0),
   ('BLD','Buildings (revaluation model)','buildings','IAS 16','revaluation','straight_line',600,0,'1510','1511','7000','3300',2.5,0),
   ('MV','Motor vehicles','motor_vehicles','IAS 16','cost','straight_line',60,10,'1520','1521','7000',NULL,20,1000),
   ('IT','Computer equipment','computer_equipment','IAS 16','cost','straight_line',36,0,'1530','1531','7000',NULL,25,500),
   ('FF','Furniture & fittings','furniture','IAS 16','cost','straight_line',120,0,'1540','1541','7000',NULL,10,500),
   ('OE','Office equipment, generators & solar','office_equipment','IAS 16','cost','straight_line',96,0,'1550','1551','7000',NULL,10,500),
   ('LHI','Leasehold improvements','leasehold_improvements','IAS 16','cost','straight_line',60,0,'1560','1561','7000',NULL,5,1000),
   ('LAB','Forensic lab equipment','forensic_lab_equipment','IAS 16','cost','straight_line',60,0,'1565','1566','7000',NULL,25,1000),
   ('SW','Software & licences','software','IAS 38','cost','straight_line',60,0,'1800','1801','7020',NULL,25,1000),
   ('IP','Investment property (fair value model)','investment_property','IAS 40','fair_value','none',NULL,0,'1700',NULL,NULL,NULL,2.5,0)
  ) AS v(code, name, cls, std, model, meth, life, resid, cost, ad, dep, res, wt, thr);

-- 32.4 Fixed asset register (assets owned at go-live, 31 Dec 2024) --------------------------
CREATE TEMP TABLE seed_assets (tag TEXT, name TEXT, cat TEXT, office TEXT, dept TEXT, custodian TEXT, make TEXT, serial TEXT, reg TEXT,
                               acq DATE, cost NUMERIC, life INT, fv2024 NUMERIC, prop TEXT, policy TEXT, qty INT DEFAULT 1);
INSERT INTO seed_assets VALUES
 ('MXH-LND-001','Maxhub House - land','LND','HRE','FAC',NULL,NULL,NULL,NULL,'2014-03-01',650000,NULL,1150000,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-BLD-001','Maxhub House - building (owner-occupied floors 1-4)','BLD','HRE','FAC',NULL,NULL,NULL,NULL,'2015-06-01',2300000,600,3400000,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-IP-001','Maxhub House - floors 5-6 let to tenants','IP','HRE','FIN',NULL,NULL,NULL,NULL,'2015-06-01',900000,NULL,1450000,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-LND-002','Maxhub Centre Bulawayo - land','LND','BYO','FAC',NULL,NULL,NULL,NULL,'2015-02-01',180000,NULL,260000,'PRP-BYO-01','HGI-PROP-2026-114',1),
 ('MXH-BLD-002','Maxhub Centre Bulawayo - building','BLD','BYO','FAC',NULL,NULL,NULL,NULL,'2015-02-01',520000,600,780000,'PRP-BYO-01','HGI-PROP-2026-114',1),
 ('MXH-LND-003','Mount Pleasant Business Park - Stand 22 (future campus)','LND','HRE','FAC',NULL,NULL,NULL,NULL,'2022-08-15',400000,NULL,520000,'PRP-HRE-02',NULL,1),
 ('MXH-MV-001','Toyota Land Cruiser Prado VX','MV','HRE','EXE','E001','Toyota Land Cruiser Prado 2.8GD','JTEBR3FJ20K100001','AFG 4410','2022-03-10',78000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-002','Toyota Fortuner 2.8GD-6','MV','HRE','EXE','E018','Toyota Fortuner 2.8GD-6','AHTKB3FS20K200002','AFB 2210','2021-06-15',52000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-003','Toyota Fortuner 2.8GD-6','MV','HRE','FAI','E002','Toyota Fortuner 2.8GD-6','AHTKB3FS20K200003','AFB 2211','2021-06-15',52000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-004','Toyota Fortuner 2.8GD-6','MV','HRE','RAS','E010','Toyota Fortuner 2.8GD-6','AHTKB3FS20K200004','AFB 2212','2021-06-15',52000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-005','Toyota Hilux 2.4GD-6 double cab','MV','HRE','FAC','E022','Toyota Hilux 2.4GD-6 D/C','AHTJB3DD20K300005','AEZ 7781','2020-09-01',45000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-006','Toyota Hilux 2.4GD-6 double cab','MV','BYO','FAC','E026','Toyota Hilux 2.4GD-6 D/C','AHTJB3DD20K300006','AEZ 7782','2021-02-01',46000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-007','Toyota Hilux 2.8GD-6 double cab','MV','HRE','FAI',NULL,'Toyota Hilux 2.8GD-6 D/C','AHTJB3DD20K300007','AGA 1920','2023-04-01',52000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-008','Nissan Navara 2.5 dCi (pool vehicle)','MV','HRE','FAC',NULL,'Nissan Navara D40','VSKCVND40U0400008','ADX 3380','2019-01-15',36000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-009','Toyota Quantum 14-seater (staff transport)','MV','HRE','FAC',NULL,'Toyota HiAce Quantum','JTFSS22P90K500009','AEY 5501','2021-08-01',42000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-010','Honda Fit hybrid (pool car)','MV','HRE','FAC',NULL,'Honda Fit Hybrid GP5','GP5-3100010','AGC 8810','2023-07-01',14000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-011','Honda Fit hybrid (pool car)','MV','HRE','FAC',NULL,'Honda Fit Hybrid GP5','GP5-3100011','AGC 8811','2023-07-01',14000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-012','Mazda BT-50 3.2 (Johannesburg)','MV','JNB','FAI','E014','Mazda BT-50 3.2 4x4','MM0UP0YF100600012','JHB 441 GP','2022-05-01',38000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-IT-SRV-001','Dell PowerEdge R760 - forensic processing server','IT','HRE','CYB','E012','Dell PowerEdge R760','SRV-R760-0001',NULL,'2023-05-15',38000,48,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-IT-SRV-002','Dell PowerEdge R760 - analytics platform server','IT','HRE','DAA','E003','Dell PowerEdge R760','SRV-R760-0002',NULL,'2023-05-15',38000,48,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-IT-NAS-001','Synology evidence storage array 400TB','IT','HRE','CYB','E012','Synology FS6400','NAS-6400-0001',NULL,'2023-05-15',24000,48,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-IT-NET-001','Core network: firewalls, switches & Wi-Fi','IT','HRE','ICT','E008','Fortinet / Cisco','NET-CORE-0001',NULL,'2022-02-01',32000,60,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-LAB-001','Forensic recovery workstations (FRED) x6','LAB','HRE','CYB','E012','Digital Intelligence FRED','FRED-6PK-0001',NULL,'2022-09-01',75000,NULL,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-LAB-002','Mobile forensics kit (UFED) #1','LAB','HRE','CYB',NULL,'Mobile extraction kit','UFED-0002',NULL,'2023-08-01',28000,NULL,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-LAB-003','Mobile forensics kit (UFED) #2','LAB','DXB','CYB',NULL,'Mobile extraction kit','UFED-0003',NULL,'2024-03-01',28000,NULL,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-LAB-004','Write-blocker & imaging field kits','LAB','HRE','CYB',NULL,'Tableau TX1 kits','TX1-KIT-0004',NULL,'2023-08-01',9500,NULL,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-FF-001','Maxhub House office furniture','FF','HRE','FAC',NULL,NULL,NULL,NULL,'2015-07-01',180000,NULL,NULL,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-FF-002','Bulawayo office furniture','FF','BYO','FAC',NULL,NULL,NULL,NULL,'2016-03-01',45000,NULL,NULL,'PRP-BYO-01','HGI-PROP-2026-114',1),
 ('MXH-FF-003','Johannesburg office furniture','FF','JNB','FAC',NULL,NULL,NULL,NULL,'2018-07-01',60000,NULL,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-FF-004','Nairobi office furniture','FF','NBO','FAC',NULL,NULL,NULL,NULL,'2021-03-01',38000,NULL,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-FF-005','London office furniture','FF','LON','FAC',NULL,NULL,NULL,NULL,'2023-01-09',52000,NULL,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-FF-006','Dubai office furniture','FF','DXB','FAC',NULL,NULL,NULL,NULL,'2024-02-01',41000,NULL,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-OE-001','Cummins 150kVA standby generator - Maxhub House','OE','HRE','FAC','E022','Cummins C150D5','GEN-150-0001',NULL,'2019-05-01',48000,NULL,NULL,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-OE-002','Cummins 60kVA standby generator - Bulawayo','OE','BYO','FAC',NULL,'Cummins C60D5','GEN-060-0002',NULL,'2019-08-01',22000,NULL,NULL,'PRP-BYO-01','HGI-PROP-2026-114',1),
 ('MXH-OE-003','120kW rooftop solar & battery system - Maxhub House','OE','HRE','FAC','E022','Hybrid PV + Li-ion storage','SOL-120-0003',NULL,'2023-10-01',85000,NULL,NULL,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-OE-004','Multifunction printers (fleet of 6)','OE','HRE','ICT',NULL,'Konica Minolta bizhub','MFP-6PK-0004',NULL,'2022-06-01',39000,60,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-OE-005','Air conditioning - Maxhub House','OE','HRE','FAC',NULL,'Daikin VRV','HVAC-0005',NULL,'2020-02-01',40000,NULL,NULL,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-OE-006','CCTV & access control','OE','HRE','FAC',NULL,'Hikvision / ZKTeco','SEC-0006',NULL,'2021-04-01',18000,NULL,NULL,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-LHI-001','Johannesburg office fit-out','LHI','JNB','FAC',NULL,NULL,NULL,NULL,'2018-07-01',95000,120,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-LHI-002','London office fit-out','LHI','LON','FAC',NULL,NULL,NULL,NULL,'2023-01-09',140000,60,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-LHI-003','Dubai office fit-out','LHI','DXB','FAC',NULL,NULL,NULL,NULL,'2024-02-01',88000,36,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-LHI-004','Arundel cyber lab - Faraday room & secure evidence store','LHI','HRE','CYB','E012',NULL,NULL,NULL,'2024-06-01',35000,36,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-SW-001','Relativity eDiscovery perpetual licence','SW','HRE','FAI','E002','Relativity Server','REL-LIC-0001',NULL,'2023-01-15',120000,60,NULL,NULL,NULL,1),
 ('MXH-SW-002','Data analytics licences (IDEA / Arbutus)','SW','HRE','DAA','E003','CaseWare IDEA / Arbutus','ANL-LIC-0002',NULL,'2024-01-10',45000,36,NULL,NULL,NULL,1);

-- laptops and phones: one per employee, tagged and assigned
INSERT INTO seed_assets (tag, name, cat, office, dept, custodian, make, serial, acq, cost, life, policy)
SELECT 'MXH-IT-' || lpad(e.employee_id::TEXT, 5, '0'),
       CASE WHEN g.level >= 5 THEN 'Laptop - Dell Latitude 9450' WHEN d.code IN ('DAA','CYB') THEN 'Laptop - Dell Precision 5690 (analytics)'
            ELSE 'Laptop - Dell Latitude 7450' END,
       'IT', o.code, d.code, e.employee_number,
       CASE WHEN g.level >= 5 THEN 'Dell Latitude 9450' WHEN d.code IN ('DAA','CYB') THEN 'Dell Precision 5690' ELSE 'Dell Latitude 7450' END,
       'DL' || upper(substr(md5(e.employee_id::TEXT), 1, 7)),
       CASE (e.employee_id % 3) WHEN 0 THEN '2022-02-14'::DATE WHEN 1 THEN '2023-02-20'::DATE ELSE '2024-03-18'::DATE END,
       CASE WHEN g.level >= 5 THEN 2400 WHEN d.code IN ('DAA','CYB') THEN 2900 ELSE 1450 END, 36, 'HGI-EEI-2026-118'
  FROM employees e JOIN job_grades g USING (job_grade_id) JOIN departments d USING (department_id) JOIN offices o ON o.office_id = e.office_id
 WHERE e.hire_date <= '2024-06-30' AND NOT (d.code = 'FAC' AND e.job_title IN ('Driver','Office Assistant'));

INSERT INTO fixed_assets (asset_tag, name, asset_category_id, property_id, status, office_id, department_id, custodian_employee_id,
                          serial_number, registration_number, make_model, acquisition_date, available_for_use_date, cost, residual_value,
                          useful_life_months, opening_date, opening_acc_depreciation, tax_value_opening, insured_value, insurance_policy_id, location_note)
SELECT s.tag, s.name, c.asset_category_id, (SELECT property_id FROM properties WHERE property_code = s.prop), 'in_use',
       (SELECT office_id FROM offices WHERE code = s.office), (SELECT department_id FROM departments WHERE code = s.dept),
       (SELECT employee_id FROM employees WHERE employee_number = s.custodian),
       s.serial, s.reg, s.make, s.acq, s.acq, s.cost, round(s.cost * c.residual_value_pct / 100, 2), s.life, '2024-12-31',
       -- accumulated depreciation at go-live (straight line, capped at depreciable amount); revalued assets restart from valuation
       CASE WHEN c.depreciation_method = 'none' OR s.fv2024 IS NOT NULL THEN 0
            ELSE LEAST(round((s.cost - s.cost * c.residual_value_pct / 100) / COALESCE(s.life, c.useful_life_months)
                        * ((extract(year FROM age('2024-12-31'::DATE, s.acq)) * 12 + extract(month FROM age('2024-12-31'::DATE, s.acq)) + 1)), 2),
                       s.cost - s.cost * c.residual_value_pct / 100) END,
       CASE WHEN c.asset_class IN ('land','investment_property') THEN s.cost
            ELSE GREATEST(round(s.cost * (1 - c.tax_wear_tear_rate_pct / 100 * (2024 - extract(year FROM s.acq) + 1)), 2), 0) END,
       COALESCE(s.fv2024, s.cost), (SELECT policy_id FROM insurance_policies WHERE policy_number = s.policy),
       (SELECT name FROM offices WHERE code = s.office)
  FROM seed_assets s JOIN asset_categories c ON c.code = s.cat;

-- legacy valuations at 31 Dec 2024 (performed before go-live: carrying amount = fair value)
INSERT INTO asset_revaluations (asset_id, valuation_date, valuation_type, valuer, fair_value, carrying_before, surplus_deficit,
                                to_oci, to_profit_or_loss, deferred_tax, fair_value_level)
SELECT fa.asset_id, '2024-12-31', CASE WHEN c.measurement_model = 'fair_value' THEN 'fair_value' ELSE 'revaluation' END,
       'Knight Frank Zimbabwe (independent valuers) - legacy valuation', s.fv2024, s.fv2024, 0, 0, 0, 0, 3
  FROM fixed_assets fa JOIN seed_assets s ON s.tag = fa.asset_tag JOIN asset_categories c ON c.asset_category_id = fa.asset_category_id
 WHERE s.fv2024 IS NOT NULL;
UPDATE fixed_assets fa SET revalued_amount = s.fv2024, last_revaluation_date = '2024-12-31'
  FROM seed_assets s WHERE s.tag = fa.asset_tag AND s.fv2024 IS NOT NULL;

INSERT INTO asset_assignments (asset_id, employee_id, assigned_date, condition_out)
SELECT asset_id, custodian_employee_id, GREATEST(acquisition_date, (SELECT hire_date FROM employees WHERE employee_id = custodian_employee_id)), 'New'
  FROM fixed_assets WHERE custodian_employee_id IS NOT NULL;

INSERT INTO asset_maintenance (asset_id, service_date, maintenance_type, description, vendor_id, cost, odometer_km, next_due_date)
SELECT fa.asset_id, d, 'service', 'Scheduled service', (SELECT vendor_id FROM vendors WHERE vendor_code = 'V019'),
       350 + (fa.asset_id % 5) * 60, 20000 + (fa.asset_id % 7) * 9000 + row_number() OVER (PARTITION BY fa.asset_id ORDER BY d) * 10000, d + 180
  FROM fixed_assets fa JOIN asset_categories c USING (asset_category_id)
 CROSS JOIN (VALUES ('2025-03-12'::DATE), ('2025-09-10'::DATE), ('2026-03-11'::DATE), ('2026-09-09'::DATE)) AS s(d)
 WHERE c.code = 'MV';
INSERT INTO asset_maintenance (asset_id, service_date, maintenance_type, description, vendor_id, cost, next_due_date)
SELECT fa.asset_id, d, 'service', '500-hour generator service & load test', (SELECT vendor_id FROM vendors WHERE vendor_code = 'V043'), 780, d + 120
  FROM fixed_assets fa CROSS JOIN (VALUES ('2025-02-05'::DATE), ('2025-06-04'::DATE), ('2025-10-08'::DATE), ('2026-02-04'::DATE), ('2026-06-03'::DATE)) AS s(d)
 WHERE fa.asset_tag IN ('MXH-OE-001','MXH-OE-002');

-- 32.5 Leases (IFRS 16) --------------------------------------------------------------------
INSERT INTO leases (lease_number, role, description, asset_class, office_id, vendor_id, currency_code, commencement_date, end_date, term_months,
                    payment_amount, payment_frequency, payment_timing, annual_escalation_pct, discount_rate_pct, deposit_paid, extension_option,
                    rou_account_code, rou_acc_dep_account_code, notes)
SELECT v.no, 'lessee', v.descr, v.cls, (SELECT office_id FROM offices WHERE code = v.office), (SELECT vendor_id FROM vendors WHERE vendor_code = v.vendor),
       v.cur, v.start::DATE, (v.start::DATE + make_interval(months => v.term) - INTERVAL '1 day')::DATE, v.term, v.pay, 'monthly', 'advance',
       v.esc, v.ibr, v.dep, v.ext, '1600', '1601', v.notes
  FROM (VALUES
   ('LSE-JNB-001','Johannesburg office - 140 West Street, 9th floor (620 m2)','property','JNB','V027','ZAR','2023-07-01',60,248000,7.0,11.75,496000,'Option to renew for 3 years - not reasonably certain','Escalates 7% each July'),
   ('LSE-NBO-001','Nairobi office - Westlands Square, 7th floor (410 m2)','property','NBO','V028','KES','2024-03-01',60,780000,5.0,14.00,1560000,'5-year renewal option - not reasonably certain','Service charge billed separately'),
   ('LSE-LON-001','London office - 1 Minster Court, 4th floor (300 m2)','property','LON','V029','GBP','2023-01-01',60,23500,0.0,7.25,70500,'Break clause at month 36 - not expected to be exercised','Rent reviewed at year 5'),
   ('LSE-DXB-001','Dubai office - DIFC Gate Village 5, level 3 (260 m2)','property','DXB','V030','AED','2024-02-01',36,52000,3.0,6.50,104000,'Renewal on market terms','DIFC fit-out approved'),
   ('LSE-HRE-001','Arundel Office Park - cyber forensics lab (180 m2)','property','HRE','V031','USD','2024-06-01',36,5400,0.0,12.50,10800,NULL,'Secure lab, Faraday room'),
   ('LSE-BYO-001','Bulawayo archive & evidence storage warehouse (240 m2)','property','BYO','V040','USD','2025-04-01',36,1850,0.0,12.50,3700,NULL,'Commenced after go-live - recognised in FY2025'),
   ('LSE-HRE-002','Borrowdale Conference Centre - Maxhub Academy training suite','property','HRE','V039','USD','2026-03-01',48,7200,5.0,12.00,14400,'Option to extend 2 years','Commenced in FY2026')
  ) AS v(no, descr, cls, office, vendor, cur, start, term, pay, esc, ibr, dep, ext, notes);

-- short-term / low-value leases use the IFRS 16 exemption (expensed in 6100)
INSERT INTO leases (lease_number, role, description, asset_class, office_id, vendor_id, currency_code, commencement_date, end_date, term_months,
                    payment_amount, exemption, status, notes)
VALUES ('LSE-HRE-ST1','lessee','Victoria Falls project site office (6 months)','property',(SELECT office_id FROM offices WHERE code='HRE'),
        (SELECT vendor_id FROM vendors WHERE vendor_code='V031'),'USD','2026-05-01','2026-10-31',6,1200,'short_term','active','Short-term lease exemption (IFRS 16.6)'),
       ('LSE-HRE-LV1','lessee','Water dispensers & shredders (low value)','equipment',(SELECT office_id FROM offices WHERE code='HRE'),
        (SELECT vendor_id FROM vendors WHERE vendor_code='V020'),'USD','2025-01-01','2027-12-31',36,180,'low_value','active','Low-value asset exemption (IFRS 16.6)');

-- lessor leases: tenants on floors 5-6 of Maxhub House (operating leases, IFRS 16.81)
INSERT INTO leases (lease_number, role, description, asset_class, property_id, tenant_name, currency_code, commencement_date, end_date, term_months,
                    payment_amount, payment_timing, annual_escalation_pct, deposit_paid, status, notes)
SELECT v.no, 'lessor', v.descr, 'property', (SELECT property_id FROM properties WHERE property_code = 'PRP-HRE-01'), v.tenant, 'USD',
       v.start::DATE, (v.start::DATE + make_interval(months => v.term) - INTERVAL '1 day')::DATE, v.term, v.rent, 'advance', 5, v.rent * 2, 'active', 'Operating lease - rental income (investing category under IFRS 18)'
  FROM (VALUES ('TEN-HRE-001','Floor 5 east wing (680 m2)','Kalahari Reinsurance Brokers (Pvt) Ltd','2023-04-01',60,6200),
               ('TEN-HRE-002','Floor 5 west wing (520 m2)','Mosi Legal Chambers','2024-01-01',36,4700),
               ('TEN-HRE-003','Floor 6 (840 m2)','Great Dyke Mining Services Ltd','2022-10-01',60,7400)) AS v(no, descr, tenant, start, term, rent);

-- 32.6 Borrowings -------------------------------------------------------------------------
INSERT INTO borrowings (loan_number, lender, purpose, currency_code, principal, interest_rate_pct, drawdown_date, term_months, security, bank_account_id)
VALUES ('CBZ-ML-2021-07','CBZ Bank Limited','Refinance of Maxhub House construction & Bulawayo purchase','USD',2400000,11.5,'2021-07-01',120,
        'First mortgage bond over Maxhub House (Stand 4412 Highlands)', (SELECT bank_account_id FROM bank_accounts WHERE name = 'Operating USD - Harare'));
DO $$ BEGIN PERFORM fn_generate_loan_schedule(loan_id) FROM borrowings; END $$;
UPDATE loan_schedule SET is_posted = TRUE WHERE due_date <= '2024-12-31';

-- schedules for leases that started before go-live; rows before go-live are "legacy posted"
UPDATE leases SET commencement_fx_rate = fn_fx_rate(currency_code, '2024-12-31')
 WHERE role = 'lessee' AND exemption IS NULL AND commencement_date < '2025-01-01';
DO $$ BEGIN PERFORM fn_generate_lease_schedule(lease_id) FROM leases WHERE role = 'lessee' AND exemption IS NULL AND commencement_date < '2025-01-01'; END $$;
UPDATE lease_schedule SET is_posted = TRUE WHERE period_date <= '2024-12-01';

-- 32.7 Opening balances at 31 December 2024 ----------------------------------------------
DO $$
DECLARE v_lines JSONB := '[]'::JSONB; v_total_dr NUMERIC; v_total_cr NUMERIC; v_je BIGINT; r RECORD; v_rate NUMERIC := 24.72;
        v_reval NUMERIC := 0; v_dtl NUMERIC := 0; v_lease_usd NUMERIC; v_rou NUMERIC;
BEGIN
    -- PPE, investment property & intangibles at go-live carrying amounts, by account
    FOR r IN SELECT ca.account_code AS cost_acc, ad.account_code AS ad_acc, SUM(COALESCE(fa.revalued_amount, fa.cost)) AS gross,
                    SUM(fa.opening_acc_depreciation) AS accdep
               FROM fixed_assets fa JOIN asset_categories c USING (asset_category_id)
               JOIN chart_of_accounts ca ON ca.account_id = c.cost_account_id
               LEFT JOIN chart_of_accounts ad ON ad.account_id = c.acc_dep_account_id
              GROUP BY 1, 2
    LOOP
        v_lines := v_lines || jsonb_build_object('acc', r.cost_acc, 'dr', r.gross, 'desc','Opening balance - cost / valuation');
        IF r.accdep > 0 THEN v_lines := v_lines || jsonb_build_object('acc', r.ad_acc, 'cr', r.accdep, 'desc','Opening accumulated depreciation'); END IF;
    END LOOP;

    -- revaluation surpluses on land & buildings (net of deferred tax) and deferred tax on investment property gains
    SELECT COALESCE(SUM(fa.revalued_amount - (fa.cost - LEAST(fa.cost, CASE WHEN c.depreciation_method = 'none' THEN 0 ELSE
                 fa.cost / c.useful_life_months * ((extract(year FROM age('2024-12-31'::DATE, fa.acquisition_date)) * 12
                 + extract(month FROM age('2024-12-31'::DATE, fa.acquisition_date))) + 1) END))), 0)
      INTO v_reval
      FROM fixed_assets fa JOIN asset_categories c USING (asset_category_id) WHERE c.measurement_model = 'revaluation';
    SELECT COALESCE(SUM(fa.revalued_amount - fa.cost), 0) INTO v_dtl
      FROM fixed_assets fa JOIN asset_categories c USING (asset_category_id) WHERE c.measurement_model = 'fair_value';
    v_lines := v_lines
      || jsonb_build_object('acc','3300','cr', round(v_reval * (1 - v_rate / 100), 2), 'desc','Revaluation reserve (net of deferred tax)')
      || jsonb_build_object('acc','2900','cr', round((v_reval + v_dtl) * v_rate / 100, 2) + 185000, 'desc','Deferred tax (revaluations, IP gains, accelerated allowances)');

    -- leases: ROU assets and lease liabilities from the schedules
    FOR r IN SELECT l.lease_id, l.rou_account_code, l.rou_acc_dep_account_code, l.initial_rou_asset, l.currency_code,
                    (SELECT SUM(rou_depreciation) FROM lease_schedule s WHERE s.lease_id = l.lease_id AND s.is_posted) AS dep,
                    (SELECT closing_liability FROM lease_schedule s WHERE s.lease_id = l.lease_id AND s.is_posted ORDER BY period_no DESC LIMIT 1) AS liab
               FROM leases l WHERE l.role = 'lessee' AND l.exemption IS NULL AND l.commencement_date < '2025-01-01'
    LOOP
        v_lease_usd := round(r.liab * fn_fx_rate(r.currency_code, '2024-12-31'), 2);
        v_lines := v_lines
          || jsonb_build_object('acc', r.rou_account_code, 'dr', r.initial_rou_asset, 'desc','Opening ROU asset')
          || jsonb_build_object('acc', r.rou_acc_dep_account_code, 'cr', r.dep, 'desc','Opening ROU accumulated depreciation')
          || jsonb_build_object('acc','2700','cr', v_lease_usd, 'desc','Opening lease liability');
        UPDATE leases SET status = 'active', liability_usd_balance = v_lease_usd, last_fx_rate = fn_fx_rate(r.currency_code, '2024-12-31')
         WHERE lease_id = r.lease_id;
    END LOOP;

    v_lines := v_lines
      || jsonb_build_object('acc','2800','cr', (SELECT closing_balance FROM loan_schedule WHERE is_posted ORDER BY period_no DESC LIMIT 1), 'desc','CBZ mortgage loan')
      -- cash & cash equivalents
      || jsonb_build_object('acc','1010','dr', 1450000) || jsonb_build_object('acc','1013','dr', 1250000)
      || jsonb_build_object('acc','1011','dr', 38000)   || jsonb_build_object('acc','1017','dr', 1500000)
      || jsonb_build_object('acc','1018','dr', 140000)  || jsonb_build_object('acc','1012','dr', 160000)
      || jsonb_build_object('acc','1014','dr', 110000)  || jsonb_build_object('acc','1015','dr', 240000)
      || jsonb_build_object('acc','1016','dr', 130000)  || jsonb_build_object('acc','1020','dr', 2500)
      -- working capital (legacy system balances)
      || jsonb_build_object('acc','1100','dr', 2180000, 'desc','Trade receivables (legacy ledger)')
      || jsonb_build_object('acc','1105','cr', 42000,   'desc','ECL allowance')
      || jsonb_build_object('acc','1300','dr', 176000,  'desc','Prepaid insurance & licences')
      || jsonb_build_object('acc','1950','dr', 142000,  'desc','Rental deposits paid to landlords')
      || jsonb_build_object('acc','2100','cr', 418000,  'desc','Trade payables (legacy ledger)')
      || jsonb_build_object('acc','2500','cr', 152000,  'desc','Accruals')
      || jsonb_build_object('acc','2200','cr', 196500,  'desc','December 2024 output VAT')
      || jsonb_build_object('acc','2210','dr', 41200,   'desc','December 2024 input VAT')
      || jsonb_build_object('acc','2400','cr', 88400,   'desc','December 2024 PAYE')
      || jsonb_build_object('acc','2405','cr', 2650,    'desc','December 2024 AIDS levy')
      || jsonb_build_object('acc','2410','cr', 14800,   'desc','December 2024 NSSA')
      || jsonb_build_object('acc','2415','cr', 3700,    'desc','December 2024 ZIMDEF')
      || jsonb_build_object('acc','2420','cr', 52000,   'desc','December 2024 pension contributions')
      || jsonb_build_object('acc','2425','cr', 21500,   'desc','December 2024 medical aid')
      || jsonb_build_object('acc','2450','cr', 61000,   'desc','Branch payroll taxes')
      || jsonb_build_object('acc','2260','cr', 342000,  'desc','FY2024 income tax balance due 30 April 2025')
      || jsonb_build_object('acc','2510','cr', 214000,  'desc','Leave pay accrual')
      || jsonb_build_object('acc','2550','cr', 90000,   'desc','Dilapidations provision - branch leases')
      || jsonb_build_object('acc','2600','cr', 158000,  'desc','Client advances')
      || jsonb_build_object('acc','2650','cr', (SELECT SUM(deposit_paid) FROM leases WHERE role = 'lessor'), 'desc','Tenant deposits held')
      || jsonb_build_object('acc','3100','cr', 1000000, 'desc','Share capital - 1,000,000 ordinary shares of USD 1');

    -- retained earnings = balancing figure
    SELECT SUM(COALESCE((x->>'dr')::NUMERIC, 0)), SUM(COALESCE((x->>'cr')::NUMERIC, 0)) INTO v_total_dr, v_total_cr
      FROM jsonb_array_elements(v_lines) x;
    v_lines := v_lines || jsonb_build_object('acc','3200','cr', round(v_total_dr - v_total_cr, 2), 'desc','Retained earnings at 31 December 2024');

    v_je := fn_post_journal('2024-12-31', 'Opening balances at go-live (migrated from legacy system, audited FY2024)', 'opening', NULL, v_lines);
    UPDATE leases SET recognised_journal_id = v_je WHERE role = 'lessee' AND exemption IS NULL AND commencement_date < '2025-01-01';
END $$;

UPDATE fiscal_periods SET is_closed = TRUE WHERE fiscal_year_id = (SELECT fiscal_year_id FROM fiscal_years WHERE name = 'FY2024');
