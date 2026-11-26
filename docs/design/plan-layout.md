# Plan layout

Plan opens with four blocks in this order.

1. **Next session.** Show the first dated training day with its date and an **Edit session** button
   wired to the same editor as the calendar. With no dated entry, show the existing recommendation
   and link to the calendar when scheduling is available.
2. **Your week.** Show the shared week strip and completed sessions against the current target.
3. **Recent break.** Ask the first unresolved question when one exists. Put any remaining questions
   with the block details.
4. **Links.** Calendar opens the full schedule. Goal opens goal and priority settings. Current block
   opens the block, upcoming blocks, findings and Ask AI. Progress opens Recovery & Progress.

The calendar and the next-session button use the same editor. The Today route for a suggested move
still opens that editor directly. The goal editor and block setup keep their native form controls.
A load failure shows a retry alongside any available content.

The owner approved implementing this layout under [#301](https://github.com/droidsam1/overreach/issues/301).
Check the spacing and reading order in light, dark and accessibility sizes under
[#21](https://github.com/droidsam1/overreach/issues/21).
