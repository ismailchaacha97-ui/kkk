import re

with open('MQL4/Indicators/VeteranTrader_Pro_V1.mq4') as f:
    code = f.read()

# Replace borderClr in CreateLine with clr
print("Checking all variables in function bodies...")
