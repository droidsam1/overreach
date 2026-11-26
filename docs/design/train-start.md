# Train start layout

[Issue #298](https://github.com/droidsam1/overreach/issues/298) · [UI consistency audit](ui-consistency-audit.md)

| State | First visible action | Below |
| --- | --- | --- |
| Next planned session | A card shows the session name, plan detail, week progress and exercises. Start workout begins the session. | Routine cards, then Start empty session. |
| No planned session, with routines | Choose a routine by tapping its card. | Start empty session remains available. |
| No planned session or routines | Start empty session is the prominent action. | The empty state points to the toolbar and History for creating routines. |
| Saved draft | Resume workout replaces the planned session and routine selection. | Discard saved workout opens confirmation. If the draft cannot be opened, Try again replaces Resume workout. |

The start page has up to four blocks. Status and retry notices share a block, followed by the next-session card,
routines and the empty-session action. Routine options keep Edit and Delete available separately from Start.
Plan checks are available under Routines. Loading keeps the existing preparation and save states distinct.

At accessibility sizes, labels and exercises wrap and the routine options stack below the start target. The owner
approved the Train layout. Compare it on an iPhone at standard and accessibility text sizes in light and dark
during [#21](https://github.com/droidsam1/overreach/issues/21).
