# Driving restrictions guide

Profile → Driving restrictions provides an offline summary for standard passenger-vehicle learner and graduated licenses in all 50 US states and DC. The driver chooses their jurisdiction and issued credential. Birthday and the original issue date refine age and elapsed-time phases; New York also requires the driving region.

## Scope and interpretation

- Hours, passenger limits, family/household exceptions and supervision appear in separate rows. Explanations and source links open on a detail page.
- This is a summary of common license restrictions, not an exhaustive determination of legal driving privileges. Printed conditions, suspensions, medical/court restrictions, local curfews and out-of-state rules remain relevant. Special, farm, hardship, motorcycle and commercial credentials need separate review.
- Age and time do not issue or upgrade a credential. Date-based phases assume valid uninterrupted driving; violations can extend them. Missing dates retain the conditional phase description. An initial period reached message requires checking the applicable exceptions and record, rather than asserting an unrestricted license.
- A full-license selection is self-reported. Age-based teen limits are retained for states whose regular/full credentials carry them; otherwise the app directs the driver to confirm the issued credential. Device-use conditions are preserved separately from curfew phases.
- Family exemptions are jurisdiction-specific. California requires documented necessity; Connecticut and Vermont exclude family during their initial phases; New Jersey dependents are not every relative; Delaware’s family exception requires a supervisor; Tennessee’s school/family exception requires a parent letter. North Carolina does not generally allow mixing household and non-household young passengers.

## Sources and maintenance

Sources were checked on 2026-10-19. Links are included in the app, with a visible source-review reminder after 180 days. The catalog does not fetch legal updates automatically. Maintain `DrivingRestrictionCatalog.swift` and its reviewed date together; verify enacted rules and current agency guidance before changing numeric limits. A bill proposal alone is not evidence of enacted law.

Primary sources are licensing agencies, official manuals and statutes. Mississippi’s 2021 enacted change was cross-checked against the 2025 codification reproduced by Justia because the legislature’s signed-law host intermittently returns 502. Both official agency and legislative links are retained. Agency manuals can have older publication dates despite being the currently linked guide; the checked date is not an assertion that the law changed that day.

The table lists the main source. Additional permit and statutory sources are embedded alongside each jurisdiction in the catalog. Source URLs are deduplicated in the UI.

| Jurisdiction | Main source |
| --- | --- |
| Alabama (AL) | [Official guide](https://www.alea.gov/dps/driver-license/license-and-id-cards/graduated-driver-license) |
| Alaska (AK) | [Official guide](https://dmv.alaska.gov/credential-services/provisional-license/) |
| Arizona (AZ) | [Official guide](https://azdot.gov/mvd/services/driver-services/teen-drivers/permit-and-license-requirements) |
| Arkansas (AR) | [Official guide](https://dps.arkansas.gov/wp-content/uploads/teen_drivers_gdl_safety_message_122015.pdf) |
| California (CA) | [Official guide](https://www.dmv.ca.gov/portal/handbook/california-driver-handbook/getting-an-instruction-permit-and-drivers-license/) |
| Colorado (CO) | [Official guide](https://dmv.colorado.gov/faq-driver-license) |
| Connecticut (CT) | [Official guide](https://portal.ct.gov/DMV/licenses-permits-ids/teen-drivers-license/driver-restrictions-teens) |
| Delaware (DE) | [Official guide](https://dmv.de.gov/DriverServices/drivers_license/index.shtml?dc=dr_lic_gdl_instruction) |
| District of Columbia (DC) | [Official guide](https://dmv.dc.gov/service/graduated-license-program) |
| Florida (FL) | [Official guide](https://www.flhsmv.gov/pdf/handbooks/englishdriverhandbook.pdf) |
| Georgia (GA) | [Official guide](https://dds.georgia.gov/resources) |
| Hawaii (HI) | [Official guide](https://hidot.hawaii.gov/highways/files/2017/01/GDL-Brochure.pdf) |
| Idaho (ID) | [Official guide](https://itd.idaho.gov/wp-content/uploads/2025/10/driver_manual.pdf) |
| Illinois (IL) | [Official guide](https://www.ilsos.gov/departments/drivers/teen-driver-safety/gdl.html) |
| Indiana (IN) | [Official guide](https://www.in.gov/bmv/licenses-permits-ids/learners-permits-and-drivers-licenses-overview/drivers-license/probationary-drivers-license/) |
| Iowa (IA) | [Official guide](https://iowadot.gov/drivers-licenses-ids/get-or-renew-drivers-licenses-ids-permits/under-18-permit-license-or-id/intermediate-license) |
| Kansas (KS) | [Official guide](https://www.ksrevenue.gov/dovgdl.html) |
| Kentucky (KY) | [Official guide](https://drive.ky.gov/Drivers/Documents/Parent%20Guide%20-Teaching-Your%20-Teen%20.pdf) |
| Louisiana (LA) | [Official guide](https://www.expresslane.org/media/qa0jml1m/louisiana-graduated-dl-program.pdf) |
| Maine (ME) | [Official guide](https://www.maine.gov/sos/bmv/driver-licenses-and-ids/car-license/license-age-restrictions) |
| Maryland (MD) | [Official guide](https://mva.maryland.gov/your-mva-guide/teens-new-drivers/provisional-license) |
| Massachusetts (MA) | [Official guide](https://www.mass.gov/info-details/teen-drivers) |
| Michigan (MI) | [Official guide](https://www.courts.michigan.gov/4add69/siteassets/publications/benchbooks/tbb/tbbresponsivehtml5.zip/TBB/Ch_3_Civil_Infraction_Nonmoving_Violations/Operating_a_Vehicle_in_Violation_of_Graduated_Licensing_Requirements.htm) |
| Minnesota (MN) | [Official guide](https://www.revisor.mn.gov/statutes/cite/171.055) |
| Mississippi (MS) | [Official guide](https://www.driverservicebureau.dps.ms.gov/Drivers/ClassR) |
| Missouri (MO) | [Official guide](https://dor.mo.gov/faq/driver-license/graduated-driver-license-law.html) |
| Montana (MT) | [Official guide](https://mvdmt.gov/new-driver-license/drivers-under-18/) |
| Nebraska (NE) | [Official guide](https://dmv.nebraska.gov/node/39) |
| Nevada (NV) | [Official guide](https://dmv.nv.gov/pdfforms/parentsguide.pdf) |
| New Hampshire (NH) | [Official guide](https://www.dmv.nh.gov/sites/g/files/ehbemt416/files/inline-documents/nhdm.pdf) |
| New Jersey (NJ) | [Official guide](https://www.nj.gov/mvc/about/gdlsafety.htm) |
| New Mexico (NM) | [Official guide](https://www.mvd.newmexico.gov/chapter-13-quick-prints/) |
| New York (NY) | [Official guide](https://dmv.ny.gov/driver-license/younger-driver/the-graduated-license-law) |
| North Carolina (NC) | [Official guide](https://www.ncdot.gov/dmv/license-id/driver-licenses/new-drivers/Pages/level2.aspx) |
| North Dakota (ND) | [Official guide](https://www.dot.nd.gov/driver/how-apply-learners-permit) |
| Ohio (OH) | [Official guide](https://bmv.ohio.gov/dl-driving-tests.aspx) |
| Oklahoma (OK) | [Official guide](https://oklahoma.gov/content/dam/service-oklahoma/intranet/job-resources/sops/a--driver-license/A.05%20-%20Intermediate%20License%20Issuance.pdf) |
| Oregon (OR) | [Official guide](https://www.oregon.gov/odot/dmv/pages/online_parent_guide_to_teen_driving/11_rules_for_graduated_licensing.aspx) |
| Pennsylvania (PA) | [Official guide](https://www.pa.gov/agencies/dmv/driver-services/pennsylvania-drivers-manual/online-drivers-manual/applying-for-a-learners-permit) |
| Rhode Island (RI) | [Official guide](https://dmv.ri.gov/licenses-permits-ids/permits-tests/new-license-permits) |
| South Carolina (SC) | [Official guide](https://dmv.sc.gov/Driver-Services/Drivers-License/Teenage-drivers) |
| South Dakota (SD) | [Official guide](https://dps.sd.gov/driver-licensing/south-dakota-licensing-information/teen-drivers) |
| Tennessee (TN) | [Official guide](https://www.tn.gov/content/dam/tn/safety/documents/DL_Manual.pdf) |
| Texas (TX) | [Official guide](https://www.dps.texas.gov/section/driver-license/texas-provisional-license-teen) |
| Utah (UT) | [Official guide](https://dld.utah.gov/teen-driver-restrictions/) |
| Vermont (VT) | [Official guide](https://dmv.vermont.gov/licenses/types-of-licenses-ids/junior-drivers-license) |
| Virginia (VA) | [Official guide](https://www.dmv.virginia.gov/licenses-ids/learners/restrictions) |
| Washington (WA) | [Official guide](https://dol.wa.gov/driver-licenses-and-permits/get-your-first-license-or-permit/driver-license-application-ages-16-17) |
| West Virginia (WV) | [Official guide](https://transportation.wv.gov/DMV/DMVFormSearch/Drivers_Licensing_Handbook_web.pdf) |
| Wisconsin (WI) | [Official guide](https://wisconsindot.gov/Pages/dmv/teen-driver/yr-frst-lcns/gdlfaqs.aspx) |
| Wyoming (WY) | [Official guide](https://dot.state.wy.us/files/live/sites/wydot/files/shared/Driver_Services/Help%20Documents%20and%20Manuals/2021%20Drivers%20License%20manual_Moto_web.pdf) |

## Privacy and verification

State, birthday, region and original issue date stay in a separate local preference record. They are not uploaded to the remote profile and do not influence route/drive scores. Account transitions clear both persisted and in-memory values. An issue date is scoped to the specific state and license stage and cannot predate birth or lie in the future.

`DrivingRestrictionsChecks.swift` verifies jurisdiction coverage, source URLs, calendar/day boundaries, family exceptions, New York regions, regular teen credentials, invalid/missing inputs, source aging and preference erasure. UI tests cover Profile entry, state/stage selection, passenger exceptions and date entry. Score-detail UI tests exercise the dial, grouped report menu and back navigation.
