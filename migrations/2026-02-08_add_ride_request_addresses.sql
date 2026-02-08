-- Add address fields to ride_requests for consistent UI display
alter table public.ride_requests
  add column if not exists pickup_address text,
  add column if not exists destination_address text;

