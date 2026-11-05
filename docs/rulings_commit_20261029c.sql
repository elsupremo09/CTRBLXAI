BEGIN TRANSACTION;
UPDATE nonweapon_equipment SET rule = 'May move through enemy-occupied tiles. Each enemy tile costs +1 movement; the through-enemy move cost is waived while the wearer has Flight. (90 BP) | USER RULING 2026-10-29: the old ''triggers compatible reactions'' clause is dropped (no such reaction exists).' WHERE id = 106;
UPDATE nonweapon_equipment SET rule = 'Trap Items placed at Range +3, and traps placed by the wearer deal +20% damage and RT delay. (90 BP) | USER RULING 2026-10-29: replaces ''remain active +500 CT'' (placed traps never expire).' WHERE id = 119;
COMMIT;