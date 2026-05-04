import clsx from 'clsx';
import type { ButtonHTMLAttributes } from 'react';

type Variant = 'primary' | 'secondary' | 'soft';

export function Button({
  variant = 'primary',
  className,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  const styles: Record<Variant, string> = {
    primary: 'bg-plum-500 text-white hover:bg-plum-600',
    secondary: 'bg-iris-500 text-white hover:bg-iris-600',
    soft: 'bg-sky-50 text-iris-800 border border-iris-100 hover:bg-sky-100',
  };
  return (
    <button
      {...rest}
      className={clsx(
        'rounded-soft px-5 py-2.5 text-sm font-medium transition-colors',
        styles[variant],
        className,
      )}
    />
  );
}
