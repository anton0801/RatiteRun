<?php

declare(strict_types=1);

namespace RatiteRun\Api\View;

/**
 * Политика конфиденциальности и условия использования.
 *
 * Текст описывает ровно то, что делает код: перечень данных сверялся
 * с миграциями и контроллерами. При изменении схемы или добавлении сбора
 * новых полей этот файл нужно править вместе с ними.
 */
final class PrivacyPage
{
    public static function render(string $lastUpdated, string $supportEmail): string
    {
        $updated = Layout::escape($lastUpdated);
        $email = Layout::escape($supportEmail);

        $content = <<<HTML
        <h1>Privacy Policy &amp; Terms of Use</h1>
        <p class="lede">
          How Ratite Run handles your data, and the terms you agree to by using it.
        </p>
        <p class="faint">Last updated: {$updated}</p>

        <div class="card accent">
          <h3 style="margin-top:0">The short version</h3>
          <ul>
            <li>No sign-up, no password, no email required to use the app.</li>
            <li>We do not sell your data, and there are no advertising or analytics trackers.</li>
            <li>Your flock records are stored so they survive losing or replacing your phone.</li>
            <li>You can export everything, and you can delete everything, from inside the app.</li>
          </ul>
        </div>

        <h2 id="who-we-are">1. Who we are</h2>
        <p>
          Ratite Run is an iOS app for people who keep ratites — ostrich, emu and rhea.
          It helps plan housing, fencing, diet, handling safety and breeding, and it
          scores how ready a holding is for the birds it keeps.
        </p>
        <p>
          This policy covers the app and this website. For anything in it, write to
          <a href="mailto:{$email}">{$email}</a> or use the
          <a href="/support-form">support form</a>.
        </p>

        <h2 id="account">2. Your account</h2>
        <p>
          The app creates an <strong>anonymous account</strong> the first time it runs.
          It sends a device identifier and receives an access key. You are never asked
          for a name, an email address or a password.
        </p>
        <p>
          You may optionally link <strong>Sign in with Apple</strong> so your flocks
          appear on more than one device. If you do, we receive the identifier Apple
          gives us, and the email address and name only if you choose to share them.
          If you use Apple's Hide My Email, we only ever see the relay address.
        </p>

        <h2 id="what-we-collect">3. What we collect</h2>

        <h3>Data you enter</h3>
        <p>
          Everything you type into the app is stored so it can be shown back to you on
          your devices: flock names, species and head counts, paddock and shelter sizes,
          fencing details, feed and grit records, handling and restraint plans, breeding
          and chick-rearing notes, health and leg-condition scores, predator and terrain
          checks, individual bird records (tag, weight, height, notes), reminders, the
          paddock layout board, review names and signature drawings, and any photos and
          markings you add.
        </p>
        <p class="hint">
          Photos are re-encoded when uploaded, which removes embedded metadata such as
          camera details and any GPS coordinates the original file carried.
        </p>

        <h3>Data the app sends automatically</h3>
        <div class="table-wrap">
        <table>
          <tr><th>Data</th><th>Why</th></tr>
          <tr>
            <td>Device identifier</td>
            <td>Ties your anonymous account to your device so reinstalling the app does not lose your flocks</td>
          </tr>
          <tr>
            <td>Platform, OS type and app version</td>
            <td>Supporting the right builds and diagnosing problems you report</td>
          </tr>
          <tr>
            <td>Time zone</td>
            <td>Delivering reminders at the hour you actually set</td>
          </tr>
          <tr>
            <td>Push notification token</td>
            <td>Only stored if you enable notifications; used to deliver care reminders</td>
          </tr>
          <tr>
            <td>IP address</td>
            <td>Security, abuse prevention and a change log of edits</td>
          </tr>
        </table>
        </div>

        <h3>Change history</h3>
        <p>
          Edits to a flock are recorded — what changed, when, and from which account and
          IP address. This exists so a holding can show an inspector or a vet when a
          fence height or a health score was last revised.
        </p>

        <h3>Support requests</h3>
        <p>
          If you contact us we keep your name, email address, subject and message, plus
          your app version and device type when the message came from inside the app.
          We keep the IP address and browser identification for 90 days as spam
          protection, then erase those two fields automatically.
        </p>

        <h3>What we never collect</h3>
        <ul>
          <li>Passwords or payment details — the app has neither.</li>
          <li>Your location. The app requests no location permission.</li>
          <li>Contacts, calendars, health data or your photo library at large — only the images you deliberately attach.</li>
          <li>Advertising identifiers. There are no ad networks and no third-party analytics in this app.</li>
        </ul>

        <h2 id="why">4. Why we are allowed to hold it</h2>
        <p>
          We process the data you enter to provide the service you asked for. We keep
          security records — IP addresses, sign-in tokens, rate limiting — because we
          have a legitimate interest in keeping accounts from being abused. Where local
          law requires consent, using the app and sending us data is that consent, and
          you can withdraw it by deleting your account.
        </p>

        <h2 id="sharing">5. Who else sees it</h2>
        <p><strong>We do not sell your data and we do not share it for advertising.</strong> It reaches other parties only here:</p>
        <ul>
          <li><strong>Apple</strong> — if you use Sign in with Apple, or receive push notifications through Apple's servers.</li>
          <li><strong>Our hosting provider</strong> — the servers and database that run the service.</li>
          <li><strong>People you send a report to.</strong> When you generate a shareable report you create a secret link to a PDF. Anyone holding that link can open it without an account, so treat it like a document you emailed. Report links expire automatically.</li>
          <li><strong>Authorities</strong> — only where we are legally compelled.</li>
        </ul>

        <h2 id="retention">6. How long we keep it</h2>
        <div class="table-wrap">
        <table>
          <tr><th>Data</th><th>Kept for</th></tr>
          <tr><td>Flock records, photos, bird records</td><td>Until you delete them, or you delete your account</td></tr>
          <tr><td>Generated report PDFs and their share links</td><td>30 days, then deleted automatically</td></tr>
          <tr><td>Sign-in tokens</td><td>Up to 90 days; revoked tokens are purged 30 days later</td></tr>
          <tr><td>IP address and browser details on support requests</td><td>90 days, then erased from the record</td></tr>
          <tr><td>Change history</td><td>For the life of the flock record</td></tr>
          <tr><td>Support message content</td><td>Until the request is resolved and no longer needed for our records</td></tr>
        </table>
        </div>

        <h2 id="rights">7. What you can do</h2>
        <ul>
          <li><strong>See it all.</strong> Settings → Backup &amp; Data → Export Data gives you every flock as a JSON file.</li>
          <li><strong>Correct it.</strong> Everything is editable in the app.</li>
          <li><strong>Delete it.</strong> Settings → Delete All Flocks removes your records. Deleting your account removes the account with them.</li>
          <li><strong>Object or complain.</strong> Write to <a href="mailto:{$email}">{$email}</a>. Depending on where you live you may also complain to your national data protection authority.</li>
        </ul>

        <h2 id="security">8. Security</h2>
        <ul>
          <li>All traffic between the app and our servers is encrypted with TLS. The app refuses unencrypted connections outright.</li>
          <li>Sign-in keys are held in the iOS Keychain, not in ordinary app storage, and are excluded from unencrypted backups.</li>
          <li>Long-lived sign-in tokens are stored only as irreversible hashes. Reusing an old one invalidates the whole chain, which limits what a stolen token is worth.</li>
          <li>Uploaded images are rebuilt from scratch server-side, which strips metadata and anything hidden inside the file.</li>
          <li>Requesting another account's records returns "not found" rather than "forbidden", so the API cannot be used to discover whether someone else's flock exists.</li>
        </ul>
        <p class="hint">
          No system is perfectly secure. If you find a vulnerability, please tell us at
          <a href="mailto:{$email}">{$email}</a> before disclosing it publicly.
        </p>

        <h2 id="children">9. Children</h2>
        <p>
          Ratite Run is built for people responsible for keeping large livestock and is
          not directed at children under 13. We do not knowingly collect their data. If
          you believe a child has sent us information, contact us and we will remove it.
        </p>

        <h2 id="transfers">10. International transfers</h2>
        <p>
          Our servers may be located in a different country from yours. Where data
          leaves your region we rely on the safeguards our hosting provider has in
          place for such transfers.
        </p>

        <h2 id="changes">11. Changes to this policy</h2>
        <p>
          If we change what we collect or why, we will update this page and the date at
          the top. Material changes will also be surfaced in the app.
        </p>

        <h2 id="terms">12. Terms of Use</h2>

        <div class="card danger">
          <h3 style="margin-top:0">Safety — read this</h3>
          <p>
            <strong>Ratites are large, powerful animals and can be dangerous.</strong>
            An ostrich or emu kicks forwards, and that kick can cause serious or fatal
            injury. Never corner a bird, always leave it an escape route, and approach
            from the side rather than head-on. Only trained handlers should attempt
            restraint.
          </p>
          <p style="margin-bottom:0">
            Every figure in this app — space per bird, fence height, protein targets,
            incubation periods, readiness scores, cost estimates — is a
            <strong>planning approximation, not veterinary or regulatory advice</strong>.
            Requirements vary by region, by holding and by individual animal. Confirm
            them with a specialist ratite vet and with your local authority before
            acting on them. Health decisions belong to a vet, not to an app.
          </p>
        </div>

        <h3>Your side of the deal</h3>
        <ul>
          <li>You are responsible for the accuracy of what you record and for the welfare of your animals.</li>
          <li>Do not use the app to break the law, to abuse the service, or to attempt access to other people's accounts.</li>
          <li>Keep your device secure. Anyone with your unlocked phone reaches your records.</li>
          <li>You keep ownership of everything you enter. You grant us only the permission needed to store it and show it back to you.</li>
        </ul>

        <h3>Our side, and its limits</h3>
        <p>
          We work to keep the service running and your data intact, but it is provided
          <strong>as is</strong>, without warranty. We are not liable for losses arising
          from reliance on the app's estimates, from service interruptions, or from data
          loss. Keep your own backups of anything that matters — the export function
          exists for this.
        </p>
        <p>
          We may suspend accounts that abuse the service. You may stop using the app at
          any time and delete your data from Settings.
        </p>

        <h2 id="contact">13. Contact</h2>
        <p>
          Questions about this policy, your data, or the app: use the
          <a href="/support-form">support form</a> or email
          <a href="mailto:{$email}">{$email}</a>.
        </p>
        HTML;

        return Layout::render(
            'Privacy Policy & Terms',
            'How Ratite Run handles your data, what it collects, how long it keeps it, and the terms of use.',
            $content,
        );
    }
}
