# Design System Specification: The Elevated Living Framework

## 1. Overview & Creative North Star
**The Creative North Star: "The Digital Concierge"**

This design system moves beyond the utility of a "management tool" to create an atmosphere of premium hospitality. Inspired by the clarity of Notion and the financial precision of Razorpay, our aesthetic is defined by **Editorial Minimalism**. 

We reject the "boxed-in" feeling of traditional apps. Instead of rigid grids and heavy borders, we use expansive whitespace, intentional asymmetry, and sophisticated tonal layering. The UI should feel like a high-end architectural magazine—structured, airy, and effortlessly calm. We don't just "show data"; we "curate information" for residents, admins, and security personnel.

---

## 2. Colors: The Tonal Depth Strategy
We utilize a sophisticated palette where color defines purpose and hierarchy, not just decoration.

### The "No-Line" Rule
**Strict Mandate:** Prohibit the use of 1px solid borders for sectioning content. To define boundaries, use background color shifts. A `surface-container-low` (#f3f4f5) section sitting on a `background` (#f8f9fa) creates a sophisticated, "borderless" division that feels more organic.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers. Use the following tiers to create depth:
*   **Base Layer:** `surface` (#f8f9fa) – The canvas.
*   **Sub-Section:** `surface-container-low` (#f3f4f5) – For grouped content.
*   **Interactive Cards:** `surface-container-lowest` (#ffffff) – The "hero" white cards that sit atop the grey background.
*   **Active Elements:** `primary-fixed` (#e2dfff) – For soft highlights.

### The "Glass & Signature Texture" Rule
*   **Glassmorphism:** For floating navigation or top bars, use `surface-container-lowest` at 80% opacity with a `backdrop-blur` of 20px.
*   **Signature Gradients:** For primary CTAs (e.g., "Pay Maintenance"), use a subtle linear gradient from `primary` (#3525cd) to `primary-container` (#4f46e5) at 135 degrees. This adds "soul" and prevents the UI from feeling flat.

---

## 3. Typography: Editorial Authority
We pair the structural precision of **Manrope** for displays with the hyper-readability of **Inter** for utility.

*   **Display & Headlines (Manrope):** Large, bold, and authoritative. Use `display-md` (2.75rem) for welcome screens to create a "hotel lobby" feel.
*   **Body & Labels (Inter):** Clean and neutral. Use `body-md` (0.875rem) for the majority of resident data to ensure high legibility on mobile devices.
*   **The Hierarchy Play:** Contrast a `headline-sm` (1.5rem, Manrope) header with a `label-sm` (0.6875rem, Inter, Uppercase) sub-header to create a high-end, editorial look.

---

## 4. Elevation & Depth: Tonal Layering
Traditional drop shadows are too "software-heavy." We use **Ambient Depth**.

*   **The Layering Principle:** Place a `surface-container-lowest` (#ffffff) card on a `surface-container-low` (#f3f4f5) background. The 2-point hex difference creates a "natural lift" that is felt rather than seen.
*   **Ambient Shadows:** For "floating" elements like FABs or Modals, use a shadow with a 40px blur, 0px spread, and 6% opacity of `on-surface` (#191c1d). This mimics natural light.
*   **Ghost Borders:** If a border is required for accessibility (e.g., in a high-glare environment for Security), use `outline-variant` (#c7c4d8) at **15% opacity**. Never use a 100% opaque border.

---

## 5. Components: Principles of Construction

### Cards & Lists (The Core of the App)
*   **Rule:** Forbid divider lines. 
*   **Implementation:** Separate list items using `spacing-4` (1.4rem) of vertical whitespace. Group related items inside a `rounded-lg` (2rem) card.
*   **Asymmetry:** In Resident Profiles, allow the profile image to slightly "break the grid" by overlapping the card header.

### Buttons
*   **Primary:** Gradient (`primary` to `primary-container`), `rounded-full`, with `label-md` typography in all caps for an elevated "Action" feel.
*   **Secondary:** `surface-container-high` background with `on-secondary-container` text. No border.

### Input Fields
*   **Style:** Minimalist. No bottom line or full box. Use a `surface-container-highest` (#e1e3e4) background with `rounded-md` (1.5rem). The label should sit `spacing-1` (0.35rem) above the field in `label-sm`.

### Society-Specific Components
*   **Visitor Pass (The "Ticket" Component):** Use a `surface-container-lowest` card with a `secondary` (#006e2f) left-edge accent (4px width). Use `display-sm` for the entry code.
*   **Status Badges:** Use `secondary-fixed` (#6bff8f) for "Approved" and `error-container` (#ffdad6) for "Overdue." These must be pill-shaped (`rounded-full`) and use `label-sm` text.

---

## 6. Do's and Don'ts

### Do:
*   **Use Whitespace as a Tool:** Use `spacing-12` (4rem) between major sections to let the UI "breathe."
*   **Nesting Surfaces:** Place a "lowest" surface on a "low" surface for natural hierarchy.
*   **Intentional Type Scaling:** Jump two steps in the type scale to show clear importance (e.g., Title-LG next to Label-SM).

### Don't:
*   **No Hard Outlines:** Never use a 1px solid #CCCCCC border. It breaks the "premium" illusion.
*   **No Pure Black Shadows:** Shadows must always be a faint tint of the surface color.
*   **No Standard Corners:** Avoid the 4px or 8px "standard" radius. Go bold with `rounded-lg` (2rem) for cards and `rounded-full` for interactive chips.
*   **No Grid Cramming:** If three cards feel tight, use a horizontal scroll (carousel) rather than shrinking the cards.

### Accessibility Note
While we prioritize soft aesthetics, ensure the `on-surface` (#191c1d) text maintains a 4.5:1 contrast ratio against all `surface-container` tiers. The "Ghost Border" should be used when visual clarity is needed for users with low vision.