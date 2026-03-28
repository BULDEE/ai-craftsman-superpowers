<?php

declare(strict_types=1);

namespace App\Infrastructure\Legacy;

final class LegacyAdapter
{
    private string $value = '';

    public function setValue(string $value): void // craftsman-ignore: no-setter
    {
        $this->value = $value;
    }
}
