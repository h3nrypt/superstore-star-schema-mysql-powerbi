# DAX Measures — KPI Card Formatting

## Overview
Custom DAX measures powering the Sales Growth KPI card, including month-over-month 
percentage change, dynamic text color, and dynamic background color via conditional 
formatting bound to field values.

## Measures

### Sales Growth
Returns a formatted month-over-month percentage change with directional arrow indicator.
Handles the first-period edge case where no prior month exists.

```dax
Sales Growth = 
VAR CM = [Total Sales]
VAR LM = 
    CALCULATE(
        [Total Sales],
        DATEADD('Dim Date'[date], -1, MONTH)
    )
VAR _perc = FORMAT(DIVIDE(CM - LM, LM), "0.0%;0.0%")
RETURN
IF(
    ISBLANK(LM),
    "N/A",
    IF(
        CM - LM >= 0,
        UNICHAR(9650) & " " & _perc,
        UNICHAR(9660) & " " & _perc
    )
)


Text Color = 
VAR CM = [Total Sales]
VAR LM = 
    CALCULATE(
        [Total Sales],
        DATEADD('Dim Date'[date], -1, MONTH)
    )
RETURN
SWITCH(
    TRUE(),
    ISBLANK(LM), "#808080",
    CM - LM > 0, "#548235",
    CM - LM < 0, "#C00000",
    "#808080"
)

BG Color = 
VAR CM = [Total Sales]
VAR LM = 
    CALCULATE(
        [Total Sales],
        DATEADD('Dim Date'[date], -1, MONTH)
    )
RETURN
SWITCH(
    TRUE(),
    ISBLANK(LM), "#F2F2F2",
    CM - LM > 0, "#E2EFDA",
    CM - LM < 0, "#FCE4E4",
    "#F2F2F2"
)


### Sales Growth
Returns a formatted month-over-month percentage change with directional arrow indicator.
Handles the first-period edge case where no prior month exists.

```dax
Profit Growth % = 
VAR CM = [Total Profit]
VAR LM = 
    CALCULATE(
        [Total Profit],
        DATEADD('Dim Date'[date], -1, MONTH)
    )
VAR _perc = FORMAT(DIVIDE(CM - LM, LM), "0.0%;0.0%")
RETURN
IF(
    ISBLANK(LM),
    "N/A",
    IF(
        CM - LM >= 0,
        UNICHAR(9650) & " " & _perc,
        UNICHAR(9660) & " " & _perc
    )
)