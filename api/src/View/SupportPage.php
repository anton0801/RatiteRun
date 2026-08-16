<?php

declare(strict_types=1);

namespace RatiteRun\Api\View;

use RatiteRun\Api\Core\Csrf;

final class SupportPage
{
    /**
     * @param array<string,string>       $old    ранее введённые значения — форма не должна обнуляться
     * @param array<string,list<string>> $errors ошибки по полям
     */
    public static function render(
        string $csrfToken,
        string $supportEmail,
        array $old = [],
        array $errors = [],
        bool $sent = false,
        ?string $formError = null,
    ): string {
        $e = static fn (string $key): string => Layout::escape($old[$key] ?? '');
        $email = Layout::escape($supportEmail);
        $token = Layout::escape($csrfToken);
        $field = Csrf::FIELD;

        $banner = '';
        if ($sent) {
            $banner = <<<HTML
            <div class="notice" role="status">
              <h3 style="margin-top:0">Message received</h3>
              <p style="margin-bottom:0">
                Thanks — we have it. We usually reply within two working days to the
                address you gave. Nothing else is needed from you right now.
              </p>
            </div>
            HTML;
        } elseif ($formError !== null) {
            $safe = Layout::escape($formError);
            $banner = <<<HTML
            <div class="notice bad" role="alert">
              <p style="margin:0"><strong>{$safe}</strong></p>
            </div>
            HTML;
        }

        $subjects = [
            'Question about using the app',
            'Something is broken',
            'My flocks are missing or out of sync',
            'Data, privacy or account deletion',
            'Species figures look wrong',
            'Feature request',
            'Something else',
        ];

        $selected = $old['subject'] ?? '';
        $options = '';
        foreach ($subjects as $subject) {
            $value = Layout::escape($subject);
            $isSelected = $selected === $subject ? ' selected' : '';
            $options .= "<option value=\"{$value}\"{$isSelected}>{$value}</option>";
        }

        $nameError    = self::fieldError($errors, 'name');
        $emailError   = self::fieldError($errors, 'email');
        $subjectError = self::fieldError($errors, 'subject');
        $messageError = self::fieldError($errors, 'message');

        $nameInvalid    = $nameError !== '' ? ' invalid' : '';
        $emailInvalid   = $emailError !== '' ? ' invalid' : '';
        $subjectInvalid = $subjectError !== '' ? ' invalid' : '';
        $messageInvalid = $messageError !== '' ? ' invalid' : '';

        $nameValue    = $e('name');
        $emailValue   = $e('email');
        $messageValue = $e('message');

        $content = <<<HTML
        <h1>Support</h1>
        <p class="lede">
          Something not working, a question about your flocks, or a figure that looks
          wrong for your birds? Send it here.
        </p>

        {$banner}

        <div class="card">
          <h3 style="margin-top:0">Before you write</h3>
          <ul style="margin-bottom:0">
            <li><strong>Flocks not appearing on a second device?</strong> Link Sign in with Apple in Settings on both devices — an anonymous account belongs to one device only.</li>
            <li><strong>Changes not saving?</strong> Check the status strip at the top of the app. "Offline" means your edits are held on the device and will go up when you have signal.</li>
            <li><strong>Need your data?</strong> Settings → Backup &amp; Data → Export Data gives you everything as a file, no request needed.</li>
            <li><strong>Health or welfare question?</strong> We cannot answer those. Call a specialist ratite vet.</li>
          </ul>
        </div>

        <form method="post" action="/support-form" novalidate>
          <input type="hidden" name="{$field}" value="{$token}">

          <!-- Ловушка для ботов: поле скрыто, человек его не увидит. -->
          <div class="hp" aria-hidden="true">
            <label for="website">Leave this field empty</label>
            <input type="text" id="website" name="website" tabindex="-1" autocomplete="off">
          </div>

          <div class="field{$nameInvalid}">
            <label for="name">Your name</label>
            <input type="text" id="name" name="name" value="{$nameValue}"
                   maxlength="120" autocomplete="name" required>
            {$nameError}
          </div>

          <div class="field{$emailInvalid}">
            <label for="email">Email</label>
            <input type="email" id="email" name="email" value="{$emailValue}"
                   maxlength="255" autocomplete="email" required>
            <p class="hint">We reply here. It is not used for anything else.</p>
            {$emailError}
          </div>

          <div class="field{$subjectInvalid}">
            <label for="subject">What is this about?</label>
            <select id="subject" name="subject" required>
              <option value="">Choose one…</option>
              {$options}
            </select>
            {$subjectError}
          </div>

          <div class="field{$messageInvalid}">
            <label for="message">Message</label>
            <textarea id="message" name="message" maxlength="5000" required
                      placeholder="What happened, and what did you expect instead? If it is about a specific flock, its name helps.">{$messageValue}</textarea>
            <p class="hint">At least 10 characters. Please do not include passwords or payment details — we never need them.</p>
            {$messageError}
          </div>

          <button type="submit">Send message</button>

          <p class="faint" style="margin-top:16px">
            Sending this stores your name, email and message so we can reply. See the
            <a href="/privacy-terms#what-we-collect">privacy policy</a> for how long we
            keep it. You can also email us directly at
            <a href="mailto:{$email}">{$email}</a>.
          </p>
        </form>
        HTML;

        return Layout::render(
            'Support',
            'Get help with Ratite Run — report a problem, ask a question, or request a feature.',
            $content,
        );
    }

    /** @param array<string,list<string>> $errors */
    private static function fieldError(array $errors, string $field): string
    {
        $messages = $errors[$field] ?? [];
        if ($messages === []) {
            return '';
        }

        $text = Layout::escape($messages[0]);

        return "<p class=\"error\">{$text}</p>";
    }
}
