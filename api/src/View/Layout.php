<?php

declare(strict_types=1);

namespace RatiteRun\Api\View;

/**
 * Оболочка страниц. Ни одного внешнего ресурса — ни шрифтов, ни скриптов
 * с CDN: это позволяет держать по-настоящему строгий CSP без 'unsafe-inline'
 * для скриптов. Палитра — из Theme.swift, чтобы веб не выглядел чужим.
 */
final class Layout
{
    public static function escape(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE | ENT_HTML5, 'UTF-8');
    }

    public static function render(string $title, string $description, string $content): string
    {
        $t = self::escape($title);
        $d = self::escape($description);
        $css = self::css();
        $year = gmdate('Y');

        return <<<HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="color-scheme" content="light dark">
        <title>{$t} · Ratite Run</title>
        <meta name="description" content="{$d}">
        <meta name="robots" content="index, follow">
        <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🦤</text></svg>">
        <style>{$css}</style>
        </head>
        <body>
        <header class="site">
          <a class="brand" href="/">
            <span class="mark" aria-hidden="true">🦤</span>
            <span>Ratite Run</span>
          </a>
          <nav>
            <a href="/privacy-terms">Privacy &amp; Terms</a>
            <a href="/support-form">Support</a>
          </nav>
        </header>

        <main>{$content}</main>

        <footer class="site">
          <p>&copy; {$year} Ratite Run. Big birds, big space, safe handling.</p>
          <p class="muted">
            Ratites are powerful animals. Nothing on this site or in the app is
            veterinary advice — consult a specialist ratite vet for health decisions.
          </p>
        </footer>
        </body>
        </html>
        HTML;
    }

    private static function css(): string
    {
        return <<<CSS
        :root {
          --bg: #FBF7EF;
          --surface: #FFFFFF;
          --border: #E8D9BD;
          --text: #3A2C12;
          --muted: #6E5A2C;
          --faint: #A89464;
          --primary: #C27D18;
          --primary-soft: rgba(224, 152, 42, .12);
          --savanna: #8A9A5B;
          --danger: #E5484D;
          --ok: #5FA84A;
          --radius: 14px;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg: #17130A;
            --surface: #211A0F;
            --border: #3A2F1B;
            --text: #F2E7D0;
            --muted: #C4B487;
            --faint: #7C6E4C;
            --primary: #E0982A;
            --primary-soft: rgba(224, 152, 42, .16);
          }
        }

        *, *::before, *::after { box-sizing: border-box; }

        body {
          margin: 0;
          background: var(--bg);
          color: var(--text);
          font: 16px/1.65 ui-rounded, "SF Pro Rounded", -apple-system,
                BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
          -webkit-text-size-adjust: 100%;
        }

        header.site {
          display: flex; align-items: center; justify-content: space-between;
          flex-wrap: wrap; gap: 12px;
          max-width: 780px; margin: 0 auto; padding: 20px 24px;
        }
        .brand {
          display: inline-flex; align-items: center; gap: 9px;
          font-weight: 700; font-size: 17px;
          color: var(--text); text-decoration: none;
        }
        .brand .mark { font-size: 22px; }
        header.site nav { display: flex; gap: 18px; }
        header.site nav a {
          color: var(--muted); text-decoration: none;
          font-size: 14px; font-weight: 600;
        }
        header.site nav a:hover { color: var(--primary); }

        main {
          max-width: 780px; margin: 0 auto;
          padding: 8px 24px 56px;
        }

        h1 {
          font-size: clamp(28px, 5vw, 38px);
          line-height: 1.2; margin: 24px 0 8px; letter-spacing: -.02em;
        }
        h2 {
          font-size: 21px; margin: 40px 0 10px;
          padding-top: 20px; border-top: 1px solid var(--border);
          letter-spacing: -.01em;
        }
        h3 { font-size: 16px; margin: 24px 0 6px; color: var(--muted); }
        p, li { color: var(--text); }
        ul { padding-left: 22px; }
        li { margin: 6px 0; }
        a { color: var(--primary); }
        strong { font-weight: 700; }

        .lede { font-size: 18px; color: var(--muted); margin-bottom: 4px; }
        .muted { color: var(--muted); font-size: 14px; }
        .faint { color: var(--faint); font-size: 13px; }

        .card {
          background: var(--surface);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: 20px 22px;
          margin: 20px 0;
        }
        .card.accent { border-color: var(--primary); background: var(--primary-soft); }
        .card.danger { border-color: var(--danger); }
        .card > :first-child { margin-top: 0; }
        .card > :last-child  { margin-bottom: 0; }

        table { width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 15px; }
        th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--border); vertical-align: top; }
        th { color: var(--muted); font-size: 13px; text-transform: uppercase; letter-spacing: .04em; }
        .table-wrap { overflow-x: auto; }

        form { margin: 24px 0; }
        .field { margin-bottom: 18px; }
        label {
          display: block; font-weight: 600; font-size: 14px;
          margin-bottom: 6px; color: var(--text);
        }
        .hint { font-size: 13px; color: var(--faint); margin: 4px 0 0; }
        input[type=text], input[type=email], select, textarea {
          width: 100%; padding: 11px 13px;
          font: inherit; font-size: 16px;
          color: var(--text); background: var(--surface);
          border: 1px solid var(--border); border-radius: 11px;
          appearance: none;
        }
        textarea { min-height: 160px; resize: vertical; }
        input:focus, select:focus, textarea:focus {
          outline: none; border-color: var(--primary);
          box-shadow: 0 0 0 3px var(--primary-soft);
        }
        .field.invalid input, .field.invalid textarea, .field.invalid select {
          border-color: var(--danger);
        }
        .error { color: var(--danger); font-size: 13px; margin: 6px 0 0; font-weight: 600; }

        button {
          font: inherit; font-weight: 700; font-size: 16px;
          color: #FFF8EA; background: var(--primary);
          border: 0; border-radius: 12px;
          padding: 13px 24px; cursor: pointer;
          width: 100%;
        }
        button:hover { filter: brightness(1.06); }
        button:active { transform: translateY(1px); }

        .notice {
          border-radius: var(--radius); padding: 16px 18px; margin: 20px 0;
          border: 1px solid var(--ok);
          background: rgba(95, 168, 74, .12);
        }
        .notice.bad { border-color: var(--danger); background: rgba(229, 72, 77, .10); }
        .notice > :first-child { margin-top: 0; }
        .notice > :last-child { margin-bottom: 0; }

        /* Ловушка для ботов: человек её не видит и не заполнит. */
        .hp { position: absolute; left: -9999px; width: 1px; height: 1px; overflow: hidden; }

        footer.site {
          max-width: 780px; margin: 0 auto;
          padding: 28px 24px 48px;
          border-top: 1px solid var(--border);
          color: var(--faint); font-size: 13px;
        }
        footer.site p { color: inherit; margin: 6px 0; }

        @media (min-width: 640px) {
          button { width: auto; min-width: 220px; }
        }
        CSS;
    }
}
