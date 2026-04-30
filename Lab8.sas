/* SECTION 1: Import*/
FILENAME REFFILE '/home/u64366633/sasuser.v94/MBA_Master.xlsx';

PROC IMPORT DATAFILE=REFFILE
    DBMS=XLSX
    OUT=WORK.WIDE
    REPLACE;
    GETNAMES=YES;
RUN;

proc datasets lib=work nolist;
    modify wide;
    rename Custid=custid Pr1=pr1 Pr2=pr2 Pr3=pr3 Pr4=pr4
           Pr5=pr5 Pr6=pr6 Pr7=pr7 Pr8=pr8;
quit;

proc transpose data=wide out=long (rename=(col1=PRODUCTS) drop=_label_);
    by custid;
    var pr1-pr8;
run;

title "SECTION 1 -";
PROC CONTENTS DATA=WORK.WIDE; RUN;
title;
/* SECTION 2: Product Customer Count + Macro Variables */
proc sql;
    create table product_customer_count as
    select products, count(distinct(custid)) as ANALYSIS_UNIT_FREQ
    from long
    where products ne ""
    group by 1;
quit;

proc sql noprint;
    select count(distinct(products)) into: product_count from long where products ne "";
    select count(distinct(custid))   into: population    from long;

    select distinct products
        into :product_1 - :product_%trim(&product_count)
        from product_customer_count
        where products ne "";

    select distinct analysis_unit_freq
        into :analysis_unit_freq_1 - :analysis_unit_freq_%trim(&product_count)
        from product_customer_count
        where products ne ""
        order by products;
quit;

title "SECTION 2 - product_customer_count";
proc print data=product_customer_count; run;
title;
/* SECTION 3: Frequency Co-Occur - Figure 7.4 */
%macro product_tot;
%do i = 1 %to &product_count;
    Proc sql;
        create table product_tot_&i as
        select products, count(distinct(custid)) as FREQ_CO_OCCUR
        from
            (select custid, products
             from long
             where custid in (select custid from long where products eq "&&product_&i"))
        where products ne ""
        group by 1
        order by 1;
    quit;
%end;
%mend;
%product_tot;

%put product is &product_1;

title "SECTION 3 - product_tot_1, LHS = &product_1 (Figure 7.4)";
proc print data=product_tot_1; run;
title;
/* SECTION 4: Metrics + Relevant 2-Way Rules - Figure 7.5 */
%macro metrics;
%do i = 1 %to &product_count;
    proc sql;
        create table metric_&i as
        select distinct "&&product_&i" as LHS, a.PRODUCTS as RHS, a.ANALYSIS_UNIT_FREQ,
            b.freq_co_occur,
            (b.FREQ_CO_OCCUR/&&analysis_unit_freq_&i)*100 as CONFIDENCE format 5.2,
            (b.FREQ_CO_OCCUR/&population)*100 as SUPPORT format 5.2,
            (a.ANALYSIS_UNIT_FREQ/&population)*100 as EXPECTED_CONFIDENCE format 5.2,
            calculated CONFIDENCE/calculated EXPECTED_CONFIDENCE as LIFT format 5.2,
            (FREQ_CO_OCCUR*(calculated LIFT-1)**2)*((calculated SUPPORT/100)*(calculated CONFIDENCE/100))
            /
            ((calculated CONFIDENCE/100 - calculated SUPPORT/100)*(calculated LIFT - calculated CONFIDENCE/100)) as CHISQ format 5.2,
            1 - Probchi(calculated CHISQ,1) as P format 5.4
        from product_customer_count as a left join product_tot_&i as b
        on a.products=b.products
        order by calculated P;
    quit;
%end;
%mend;
%metrics;

proc sql noprint;
    select memname into :datasets separated by ' '
    from dictionary.tables
    where libname = "WORK" and memname like "METRIC%";
quit;

data summary;
    format LHS $50.;
    set &datasets;
    if LHS ne RHS;
run;

data relevant (drop=analysis_unit_freq);
    set summary;
    if freq_co_occur ge 50;
    if P le 0.05;
    if confidence ge 60;
    if lift gt 1;
run;

proc sort data=relevant;
    by descending lift;
run;

title "SECTION 4 - RELEVANT 2-way rules (Figure 7.5)";
proc print data=relevant; run;
title;
/* SECTION 5: Condense - Figure 7.6 */
data condense;
    set relevant;
    if lhs not in ("Personal_Current_Account",
                   "Savings_Account",
                   "Credit_Card",
                   "Locker",
                   "Personal_Loans");
run;

title "SECTION 5 - CONDENSE (Figure 7.6)";
proc print data=condense; run;
title;
/* SECTION 6: 3-Way Metrics - Figure 7.7 */

/* Build matrix of all valid 3-product sequences */
data one;
    input id $ product1 $50.;
    datalines;
1 BTL_Mortgage|
2 Business_Current_Account|
3 Credit_Card|
4 Currency_Services|
5 Insurance|
6 Locker|
7 Personal_Current_Account|
8 Personal_Loans|
9 Premium_Current_Account|
10 Residential_Mortgage|
11 Savings_Account|
12 Trading_Account|
;

data two;
    input id $ product2 $50.;
    datalines;
1 BTL_Mortgage|
2 Business_Current_Account|
3 Credit_Card|
4 Currency_Services|
5 Insurance|
6 Locker|
7 Personal_Current_Account|
8 Personal_Loans|
9 Premium_Current_Account|
10 Residential_Mortgage|
11 Savings_Account|
12 Trading_Account|
;

data three;
    input id $ product3 $50.;
    datalines;
1 BTL_Mortgage
2 Business_Current_Account
3 Credit_Card
4 Currency_Services
5 Insurance
6 Locker
7 Personal_Current_Account
8 Personal_Loans
9 Premium_Current_Account
10 Residential_Mortgage
11 Savings_Account
12 Trading_Account
;
run;

data stage1;
    set one;
    do i = 1 to n;
        set two point=i nobs=n;
        output;
    end;
run;

data stage2;
    set stage1;
    do i = 1 to n;
        set three point=i nobs=n;
        output;
    end;
run;

data matrix (drop = lhand1 lhand2);
    set stage2 (drop = id);
    if product1 ne product2;
    if product1 ne product3;
    if product2 ne product3;
    combo  = compress(product1 || product2 || product3);
    lhand1 = scan(combo, 1);
    lhand2 = scan(combo, 2);
    lhand  = compress(lhand1 || "|" || lhand2);
run;

/* Pattern finding */
proc sql noprint;
    select count(distinct(combo)) into :combo_count from matrix;
    select distinct combo into :combo_1 - :combo_%trim(&combo_count) from matrix;
    select count(distinct(lhand)) into :lhand_count from matrix;
    select distinct lhand into :lhand_1 - :lhand_%trim(&lhand_count) from matrix;
quit;

%macro combo_find;
%do i = 1 %to &combo_count;
    proc sql;
        create table combos_main_&i as
        select a.*,
            compress(pr1||"|"||pr2||"|"||pr3||"|"||pr4||"|"||pr5||"|"||pr6||"|"||pr7||"|"||pr8) as combo,
            "&&combo_&i" as pattern_found,
            case when calculated combo contains "&&combo_&i" then 1 else 0 end as combo_count
        from wide as a;

        create table combos_sum_&i as
        select pattern_found, sum(combo_count) as freq_co_occur
        from combos_main_&i
        group by 1
        having freq_co_occur ge 1
        order by calculated freq_co_occur desc;
    quit;
%end;
%mend;
%combo_find;

%macro lhand_find;
%do i = 1 %to &lhand_count;
    proc sql;
        create table lhand_main_&i as
        select a.*,
            compress(pr1||"|"||pr2||"|"||pr3||"|"||pr4||"|"||pr5||"|"||pr6||"|"||pr7||"|"||pr8) as combo,
            "&&lhand_&i" as lhand,
            case when calculated combo contains "&&lhand_&i" then 1 else 0 end as lhand_count
        from wide as a;

        create table lhand_sum_&i as
        select lhand, sum(lhand_count) as lhand_co_occur
        from lhand_main_&i
        group by 1
        having lhand_co_occur ge 1
        order by calculated lhand_co_occur desc;
    quit;
%end;
%mend;
%lhand_find;

/* Build 3-way metrics */
proc sql noprint;
    select memname into :combosets separated by ' '
    from dictionary.tables
    where libname eq "WORK" and memname like "COMBOS_SUM_%";
quit;

data combos_main (drop = lhand1 lhand2);
    format pattern_found $200.;
    set &combosets;
    lhand1 = scan(pattern_found, 1);
    lhand2 = scan(pattern_found, 2);
    lhand  = compress(lhand1 || "|" || lhand2);
    rhand  = scan(pattern_found, -1);
run;

proc sort data=combos_main;
    by descending freq_co_occur;
run;

proc sql noprint;
    select memname into :lhandsets separated by ' '
    from dictionary.tables
    where libname eq "WORK" and memname like "LHAND_SUM_%";
quit;

data lhand_main;
    format lhand $200.;
    set &lhandsets;
run;

proc sql;
    create table metric_three_way as
    select distinct a.LHAND as LHS, a.RHAND as RHS, c.lhand_co_occur as ANALYSIS_UNIT_FREQ,
        a.freq_co_occur,
        (a.FREQ_CO_OCCUR/c.lhand_co_occur)*100 as CONFIDENCE format 5.2,
        (a.FREQ_CO_OCCUR/&population)*100 as SUPPORT format 5.2,
        (d.analysis_unit_freq/&population)*100 as EXPECTED_CONFIDENCE format 5.2,
        calculated CONFIDENCE/calculated EXPECTED_CONFIDENCE as LIFT format 5.2,
        (a.FREQ_CO_OCCUR*(calculated LIFT-1)**2)*((calculated SUPPORT/100)*(calculated CONFIDENCE/100))
        /
        ((calculated CONFIDENCE/100 - calculated SUPPORT/100)*(calculated LIFT - calculated CONFIDENCE/100)) as CHISQ format 5.2,
        1 - Probchi(calculated CHISQ,1) as P format 5.4
    from combos_main as a left join product_customer_count as b
    on a.lhand=b.products
    left join lhand_main as c on a.lhand=c.lhand
    left join product_customer_count as d on a.rhand=d.products
    order by calculated P, calculated confidence desc, calculated expected_confidence desc;
quit;

title "SECTION 6 - METRIC_THREE_WAY (Figure 7.7)";
proc print data=metric_three_way; run;
title;
/* SECTION 7: Relaxed 3-Way Rules - Figure 7.8 */
data relevant_three_way;
    set metric_three_way;
    if confidence ge 40;
    if lift gt 1;
    if freq_co_occur ge 25;
run;

title "SECTION 7 - RELEVANT 3-way relaxed (Figure 7.8)";
proc print data=relevant_three_way (drop=chisq p); run;
title;