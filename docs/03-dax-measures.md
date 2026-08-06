# DAX Measures — KPI Card Formatting

## Overview
Custom DAX measures powering the Sales and Profit KPI cards, including 
month-over-month percentage change, dynamic text color, and dynamic background 
color via conditional formatting bound to field values.

## Sales Card Measures

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
```

### Text Color
Drives font color on the Sales Growth callout via conditional formatting 
(Format style: Field value).

```dax
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
```

### BG Color
Drives background color on the Sales card via conditional formatting 
(Format style: Field value). Uses lighter tints so text remains readable.

```dax
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
```

## Profit Card Measures

### LM Profit
Displays the prior month's profit value as comparison text below the main callout.
Guards against blank prior-period data at the start of the date range.

```dax
LM Profit = 
VAR LM =
    CALCULATE(
        [Total Profit],
        DATEADD('Dim Date'[date], -1, MONTH)
    )
RETURN
IF(
    ISBLANK(LM),
    "No prior month data",
    "VS " & FORMAT(LM, "$#,.0K") & " Last Month"
)
```

### Profit Growth %
Returns a formatted month-over-month percentage change with directional arrow indicator.
Mirrors the Sales Growth measure structure for consistency across cards.

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
```

### Profit Text Color
Drives font color on the Profit Growth callout via conditional formatting 
(Format style: Field value).

```dax
Profit Text Color = 
VAR CM = [Total Profit]
VAR LM = 
    CALCULATE(
        [Total Profit],
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
```

### Profit BG Color
Drives background color on the Profit card via conditional formatting 
(Format style: Field value).

```dax
Profit BG Color = 
VAR CM = [Total Profit]
VAR LM = 
    CALCULATE(
        [Total Profit],
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
```

## Color Reference

Shared across both Sales and Profit cards for visual consistency — one color 
language across the dashboard, not two.

| State | Text Color | Background Color |
|---|---|---|
| Growth (up) | `#548235` | `#E2EFDA` |
| Decline (down) | `#C00000` | `#FCE4E4` |
| No prior period / neutral | `#808080` | `#F2F2F2` |

## Implementation Notes — Conditional Formatting Binding

1. Select the card visual → **Format visual**.
2. Locate the field displaying the growth measure (Sales Growth or Profit Growth %).
3. Font color → fx icon → **Format style: Field value** → base field: 
   `Text Color` (Sales) or `Profit Text Color` (Profit).
4. Background color → fx icon → **Format style: Field value** → base field: 
   `BG Color` (Sales) or `Profit BG Color` (Profit).
5. Not all card visual types expose per-field conditional formatting on secondary 
   text fields — verify the visual type supports this before assuming a binding failed.

## Sparkline Formatting Notes

- Y-axis minimum set to **0** (not auto-scale). Auto-scale exaggerates day-to-day 
  noise by anchoring the axis to the local min instead of true zero, making minor 
  fluctuations look like dramatic swings.
- Y-axis maximum left on auto — no distortion risk on the upper bound.
- Sparkline color kept neutral (not tied to growth/decline state) — a deliberate 
  choice to avoid competing with the primary up/down indicator on the same card.

## Known Edge Case
`DATEADD` returns `BLANK()` for the first period in the date range (no prior month 
exists). Without an explicit `ISBLANK(LM)` check, `CM - BLANK()` evaluates as `CM`, 
which is falsely `> 0` — this would silently misreport the first data point as growth. 
All measures above guard against this explicitly. Any future period-over-period 
measure added to this model must include the same guard.

## Business Insight — Sales/Profit Divergence
March 2016 showed sales growth well above trend while profit declined in the same 
period — a real, explainable pattern rather than a data error. Likely drivers, in 
order of investigation priority: heavier discounting on higher sales volume, a 
product mix shift toward lower-margin categories (Furniture, particularly Tables), 
or a small number of high-discount, negative-profit outlier orders concentrated in 
that month. Diagnosing this required breaking Sales and Profit down by Category and 
Sub-Category for the affected period rather than trusting the headline KPI numbers 
alone.