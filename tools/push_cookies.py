#!/usr/bin/env python3
"""Push a cookies file into an installed app's Documents/ on a USB device.

Uses pymobiledevice3's house_arrest (VendDocuments) service so no jailbreak
or tunnel is needed. Called by `make install COOKIESFILE=…` (device branch).

Usage:
    push_cookies.py --bundle-id BID --local PATH [--udid UDID] [--remote /cookies.txt]
"""

import argparse
import asyncio
import os
import sys


async def run(args: argparse.Namespace) -> int:
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.services.house_arrest import HouseArrestService

    lockdown = await create_using_usbmux(serial=args.udid or None)
    async with await HouseArrestService.create(
        lockdown, args.bundle_id, documents_only=True
    ) as house:
        await house.push(args.local, args.remote)
        if not await house.exists(args.remote):
            print(f"ERROR: push did not land at {args.remote}", file=sys.stderr)
            return 1
        print(
            f"cookies delivered: {os.path.basename(args.local)} -> "
            f"Documents{args.remote} on {lockdown.short_info.get('DeviceName', 'device')}"
        )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", default=None, help="device UDID (default: first usbmux device)")
    parser.add_argument("--bundle-id", required=True, help="installed app bundle identifier")
    parser.add_argument("--local", required=True, help="local cookies file to push")
    parser.add_argument(
        "--remote", default="/cookies.txt",
        help="path inside the app's Documents directory (default: /cookies.txt)",
    )
    args = parser.parse_args()
    if not os.path.isfile(args.local):
        print(f"ERROR: local file not found: {args.local}", file=sys.stderr)
        return 1
    return asyncio.run(run(args))


if __name__ == "__main__":
    sys.exit(main())
