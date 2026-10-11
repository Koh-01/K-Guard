# K Guard Design System

Adapted from the Vercel reference in `awesome-design-md` for a field-security
mobile application. The interface is intentionally quiet, precise, and easy to
scan outdoors. Color communicates state; it is not decoration.

## 1. Visual direction

- Cold gray application canvas with clean white working surfaces.
- Near-black text and controls instead of pure black to reduce glare.
- One regular accent: focused blue. Green, amber, and red are reserved for
  success, attention, and danger states.
- Structure comes from spacing and hairline shadow-borders, not heavy shadows.
- UI copy is compact and direct. Important actions remain obvious at a glance.

## 2. Color roles

### Light

- Canvas: `#F5F5F5`
- Surface: `#FFFFFF`
- Raised/subtle surface: `#FAFAFA`
- Primary text / primary action: `#171717`
- Secondary text: `#666666`
- Muted text: `#808080`
- Hairline: `rgba(0, 0, 0, 0.08)`
- Focus / link: `#0A72EF`
- Success: `#16803C`
- Warning: `#B45309`
- Danger: `#D92D20`

### Dark

- Canvas: `#090909`
- Surface: `#141414`
- Raised/subtle surface: `#1C1C1C`
- Primary text / primary action: `#F5F5F5`
- Secondary text: `#A3A3A3`
- Hairline: `rgba(255, 255, 255, 0.10)`
- Focus / link: `#57A0FF`

## 3. Typography

- Use the platform sans-serif with Arial fallback.
- Headings: weight 600, slightly negative letter spacing.
- Interactive labels: weight 500.
- Body: weight 400 with relaxed line height.
- Use tabular figures for counters, timestamps, and progress values.
- Do not use bold body text or decorative positive tracking.

## 4. Components

### Buttons

- Primary: near-black fill, white label, 8px radius, 48px minimum height.
- Secondary: white surface, subtle hairline, near-black label.
- Destructive actions use red only when the consequence is destructive.
- Disabled controls use neutral gray rather than reduced-opacity color noise.

### Cards and containers

- Surface: white.
- Radius: 12px.
- Border treatment: zero-offset 1px shadow at 8% black.
- Optional elevation: add a 2px blur at 4% black.
- Avoid nesting cards unless the inner element is interactive.

### Inputs

- Filled white surface on the gray canvas.
- 8px radius and neutral hairline border.
- Blue 2px focus border.
- Labels remain visible; placeholders never replace required labels.

### Status

- Pills are used only for short status text.
- Blue: informational/in progress.
- Green: successful/complete.
- Amber: attention/pending.
- Red: failed/danger.

### Navigation

- White or near-black top bar with no elevation.
- Bottom navigation uses a subtle top hairline and compact labels.
- Active destinations use a neutral filled indicator; SOS remains red.

## 5. Layout

- Base spacing unit: 8px.
- Screen horizontal padding: 16px on compact phones, 24px on wide screens.
- Section gaps: 24–32px.
- Component gaps: 8–16px.
- Maximum content width: 720px for forms and settings, centered on tablets.
- Touch targets are at least 44px.

## 6. Motion and depth

- Keep motion functional and brief (150–220ms).
- No decorative looping animation.
- Shadows stay below 10% opacity.
- Loading states preserve the shape and location of the final action.

## 7. Guardrails

- Do not add gradients, glassmorphism, or purple UI chrome.
- Do not use color for decoration.
- Do not use mixed corner-radius systems.
- Do not rely on color alone for status; pair it with text or an icon.
- Do not alter NFC, GPS, camera, reporting, storage, or account behavior as part
  of visual work.

## 8. Responsive behavior

- Below 400px, reduce outer padding to 16px and stack multi-column content.
- From 600px, center content and allow two-column profile/category grids.
- Lists remain single-column for fast field scanning.
- Bottom actions respect safe areas on every device.

