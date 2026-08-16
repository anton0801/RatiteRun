-- Справочные данные, перенесённые из Presets.swift.
-- Дальше правятся в БД без релиза приложения.

INSERT INTO species_presets
    (species, locale, adult_mass_kg, space_per_bird_m2, min_space_per_bird_m2,
     rec_fence_height_m, min_fence_height_m, rec_fence_strength,
     incubation_days, egg_mass_g, kick_risk_level, target_protein_pct,
     grit_importance, leg_issue_risk, hatch_window_days, updated_at)
VALUES
    ('ostrich', 'en', 115.00, 300.00, 250.00, 2.00, 1.80, 5, 42, 1500.00, 5, 16.00, 5, 5, 4, UTC_TIMESTAMP(3)),
    ('emu',     'en',  40.00, 200.00, 150.00, 1.80, 1.50, 4, 52,  600.00, 4, 17.00, 4, 3, 6, UTC_TIMESTAMP(3)),
    ('rhea',    'en',  25.00, 130.00, 100.00, 1.50, 1.20, 3, 38,  600.00, 4, 18.00, 4, 3, 5, UTC_TIMESTAMP(3))
AS new
ON DUPLICATE KEY UPDATE
    adult_mass_kg         = new.adult_mass_kg,
    space_per_bird_m2     = new.space_per_bird_m2,
    min_space_per_bird_m2 = new.min_space_per_bird_m2,
    rec_fence_height_m    = new.rec_fence_height_m,
    min_fence_height_m    = new.min_fence_height_m,
    rec_fence_strength    = new.rec_fence_strength,
    incubation_days       = new.incubation_days,
    egg_mass_g            = new.egg_mass_g,
    kick_risk_level       = new.kick_risk_level,
    target_protein_pct    = new.target_protein_pct,
    grit_importance       = new.grit_importance,
    leg_issue_risk        = new.leg_issue_risk,
    hatch_window_days     = new.hatch_window_days,
    updated_at            = UTC_TIMESTAMP(3);

INSERT INTO content_blocks (slug, locale, body, updated_at)
VALUES
    ('disclaimer', 'en',
     'Ratites are large, powerful birds and can be dangerous — a forward kick can cause serious injury. Follow safe handling and never corner a bird. Figures are estimates for planning only; consult a specialist ratite vet for health decisions.',
     UTC_TIMESTAMP(3)),
    ('handling-rules.ostrich', 'en',
     'Kick risk for Ostrich: Extreme — the forward kick is the danger.\nNever corner the bird — always leave an escape route.\nApproach from the side, not head-on.\nUse a hood to calm before restraint.\nOnly trained handlers should restrain.',
     UTC_TIMESTAMP(3)),
    ('handling-rules.emu', 'en',
     'Kick risk for Emu: High — the forward kick is the danger.\nNever corner the bird — always leave an escape route.\nApproach from the side, not head-on.\nUse a hood to calm before restraint.\nOnly trained handlers should restrain.',
     UTC_TIMESTAMP(3)),
    ('handling-rules.rhea', 'en',
     'Kick risk for Rhea: High — the forward kick is the danger.\nNever corner the bird — always leave an escape route.\nApproach from the side, not head-on.\nUse a hood to calm before restraint.\nOnly trained handlers should restrain.',
     UTC_TIMESTAMP(3))
AS new
ON DUPLICATE KEY UPDATE body = new.body, updated_at = UTC_TIMESTAMP(3);
