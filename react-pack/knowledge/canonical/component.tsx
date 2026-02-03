/**
 * CANONICAL REACT COMPONENT PATTERN
 *
 * Key characteristics:
 * - forwardRef for ref forwarding
 * - Proper TypeScript types
 * - Composable with className
 * - Accessible by default
 * - Named export (no default)
 */

import {
  forwardRef,
  type ComponentPropsWithoutRef,
  type ReactNode,
} from 'react';
import { cn } from '@/lib/cn';

// ============================================
// SIMPLE COMPONENT
// ============================================

export interface ButtonProps extends ComponentPropsWithoutRef<'button'> {
  /** Visual style variant */
  readonly variant?: 'primary' | 'secondary' | 'ghost' | 'danger';
  /** Size of the button */
  readonly size?: 'sm' | 'md' | 'lg';
  /** Show loading spinner */
  readonly isLoading?: boolean;
  /** Icon to display before text */
  readonly leftIcon?: ReactNode;
  /** Icon to display after text */
  readonly rightIcon?: ReactNode;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  (
    {
      className,
      variant = 'primary',
      size = 'md',
      isLoading = false,
      leftIcon,
      rightIcon,
      disabled,
      children,
      ...props
    },
    ref
  ) => {
    return (
      <button
        ref={ref}
        disabled={disabled || isLoading}
        className={cn(
          // Base styles
          'inline-flex items-center justify-center font-medium transition-colors',
          'focus:outline-none focus:ring-2 focus:ring-offset-2',
          'disabled:opacity-50 disabled:cursor-not-allowed',
          // Variants
          {
            'bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500':
              variant === 'primary',
            'bg-gray-200 text-gray-900 hover:bg-gray-300 focus:ring-gray-500':
              variant === 'secondary',
            'bg-transparent text-gray-700 hover:bg-gray-100 focus:ring-gray-500':
              variant === 'ghost',
            'bg-red-600 text-white hover:bg-red-700 focus:ring-red-500':
              variant === 'danger',
          },
          // Sizes
          {
            'text-sm px-3 py-1.5 rounded': size === 'sm',
            'text-base px-4 py-2 rounded-md': size === 'md',
            'text-lg px-6 py-3 rounded-lg': size === 'lg',
          },
          className
        )}
        {...props}
      >
        {isLoading && (
          <svg
            className="animate-spin -ml-1 mr-2 h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
          >
            <circle
              className="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              strokeWidth="4"
            />
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
            />
          </svg>
        )}
        {!isLoading && leftIcon && <span className="mr-2">{leftIcon}</span>}
        {children}
        {!isLoading && rightIcon && <span className="ml-2">{rightIcon}</span>}
      </button>
    );
  }
);

Button.displayName = 'Button';

// ============================================
// COMPOUND COMPONENT PATTERN
// ============================================

export interface CardProps extends ComponentPropsWithoutRef<'div'> {
  readonly variant?: 'default' | 'elevated';
}

export const Card = forwardRef<HTMLDivElement, CardProps>(
  ({ className, variant = 'default', ...props }, ref) => {
    return (
      <div
        ref={ref}
        className={cn(
          'rounded-lg border bg-white',
          {
            'border-gray-200': variant === 'default',
            'border-gray-200 shadow-lg': variant === 'elevated',
          },
          className
        )}
        {...props}
      />
    );
  }
);

Card.displayName = 'Card';

export const CardHeader = forwardRef<
  HTMLDivElement,
  ComponentPropsWithoutRef<'div'>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn('px-6 py-4 border-b border-gray-200', className)}
    {...props}
  />
));

CardHeader.displayName = 'CardHeader';

export const CardTitle = forwardRef<
  HTMLHeadingElement,
  ComponentPropsWithoutRef<'h3'>
>(({ className, ...props }, ref) => (
  <h3
    ref={ref}
    className={cn('text-lg font-semibold text-gray-900', className)}
    {...props}
  />
));

CardTitle.displayName = 'CardTitle';

export const CardContent = forwardRef<
  HTMLDivElement,
  ComponentPropsWithoutRef<'div'>
>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn('px-6 py-4', className)} {...props} />
));

CardContent.displayName = 'CardContent';

// ============================================
// POLYMORPHIC COMPONENT
// ============================================

type AsProp<C extends React.ElementType> = {
  as?: C;
};

type PropsToOmit<C extends React.ElementType, P> = keyof (AsProp<C> & P);

type PolymorphicComponentProp<
  C extends React.ElementType,
  Props = object,
> = React.PropsWithChildren<Props & AsProp<C>> &
  Omit<React.ComponentPropsWithoutRef<C>, PropsToOmit<C, Props>>;

interface TextOwnProps {
  readonly variant?: 'body' | 'heading' | 'caption';
}

type TextProps<C extends React.ElementType> = PolymorphicComponentProp<
  C,
  TextOwnProps
>;

export function Text<C extends React.ElementType = 'span'>({
  as,
  variant = 'body',
  className,
  children,
  ...props
}: TextProps<C>) {
  const Component = as || 'span';

  return (
    <Component
      className={cn(
        {
          'text-base text-gray-700': variant === 'body',
          'text-2xl font-bold text-gray-900': variant === 'heading',
          'text-sm text-gray-500': variant === 'caption',
        },
        className
      )}
      {...props}
    >
      {children}
    </Component>
  );
}

// Usage:
// <Text>Default span</Text>
// <Text as="p">Paragraph</Text>
// <Text as="h1" variant="heading">Heading</Text>
