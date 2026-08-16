<?php

declare(strict_types=1);

namespace RatiteRun\Api\View;

/**
 * Минимальная главная. Существует, чтобы ссылки в шапке и в App Store вели
 * на живую страницу, а не в 404.
 */
final class HomePage
{
    public static function render(string $supportEmail): string
    {
        $email = Layout::escape($supportEmail);

        $content = <<<HTML
        <h1>Big birds, big space, safe handling.</h1>
        <p class="lede">
          Ratite Run is an iOS app for people who keep ostrich, emu and rhea. It turns
          what you know about your holding into a straight answer: is this set-up
          actually ready for these birds?
        </p>

        <div class="card">
          <h3 style="margin-top:0">What it does</h3>
          <ul style="margin-bottom:0">
            <li><strong>Scores readiness.</strong> Space, fencing, diet, grit and water, handling safety and leg health, weighted into one figure you can act on.</li>
            <li><strong>Knows the species.</strong> An ostrich needs roughly 300 m² per bird and a two-metre fence; a rhea needs far less. The app holds those figures so you do not have to.</li>
            <li><strong>Takes handling seriously.</strong> Ratites kick forwards, and it hurts. The app scores your handling protocol and states the rules plainly.</li>
            <li><strong>Produces a report.</strong> A clean PDF for a vet, an inspector or your own records.</li>
          </ul>
        </div>

        <div class="card accent">
          <h3 style="margin-top:0">No account, no password</h3>
          <p style="margin-bottom:0">
            The app works the moment you open it. Your records are backed up so a lost
            phone does not mean lost records, and you can export or delete everything
            from Settings whenever you want.
          </p>
        </div>

        <h2>Get in touch</h2>
        <p>
          Questions, problems, or a figure that looks wrong for your birds — use the
          <a href="/support-form">support form</a> or email
          <a href="mailto:{$email}">{$email}</a>.
        </p>
        <p class="muted">
          See also the <a href="/privacy-terms">privacy policy and terms of use</a>.
        </p>
        HTML;

        return Layout::render(
            'Ratite Run',
            'Planning and safety app for keepers of ostrich, emu and rhea.',
            $content,
        );
    }
}
